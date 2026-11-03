# lib/kollective_web/controllers/businesses/proposal_comment_controller.ex
defmodule KollectiveWeb.ProposalCommentController do
  @moduledoc """
  Threaded discussion engine for Business Proposals.

  Mirrors `KollectiveWeb.EventCommentController` (moderation gate, R2 image
  pre-signing, Oban mention/image workers, PubSub fan-out) while adding the
  state-level geofence: only verified residents of the proposal's state may
  read or write inside its discussion channel.
  """
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Businesses.{Business, Businesses}
  alias Kollective.Locations.StateGate
  alias Kollective.Moderation.Moderation
  alias Kollective.Security.Security
  alias KollectiveWeb.{ChangesetJSON, ProposalCommentJSON}

  # Throttle the endpoint to protect the database from script flooding
  plug KollectiveWeb.Plugs.RateLimiter when action in [:create]

  # GET /api/v1/proposal_comments?proposal_id=01J0A...
  def index(conn, %{"proposal_id" => proposal_id} = params) do
    with {:ok, proposal} <- fetch_proposal(proposal_id),
         :ok <- authorize_state(conn, proposal, :read) do
      comments = Businesses.list_proposal_comments(proposal.id, params)

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: ProposalCommentJSON.index(%{comments: comments})
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Proposal not found."})

      {:error, :locked} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", error: StateGate.locked_message()})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: to_string(reason)})
    end
  end

  def index(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", error: "proposal_id query parameter is required."})
  end

  # GET /api/v1/proposal_comments/:id
  def show(conn, %{"id" => id}) do
    case Businesses.get_proposal_comment(id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Comment not found or access is restricted."})

      {:ok, comment} ->
        with {:ok, proposal} <- fetch_proposal(comment.business_id) do
          if StateGate.locked?(Businesses.proposal_state_code(proposal), actor_state(conn)) do
            conn
            |> put_status(:forbidden)
            |> json(%{status: "error", error: StateGate.locked_message()})
          else
            conn
            |> put_status(:ok)
            |> json(%{status: "success", data: ProposalCommentJSON.data(comment)})
          end
        else
          _ ->
            conn
            |> put_status(:not_found)
            |> json(%{status: "error", error: "Proposal not found."})
        end
    end
  end

  # POST /api/v1/proposals_comments/:proposal_id/comment
  def create(conn, %{"proposal_id" => proposal_id} = params) do
    with {:ok, proposal} <- fetch_proposal(proposal_id),
         :ok <- authorize_state(conn, proposal, :write) do
      insert_comment(conn, proposal, params)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Proposal not found."})

      {:error, :locked} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", error: StateGate.locked_message()})
    end
  end

  # GET /api/v1/proposal_comments/image/presign
  # Expected params: ?content_type=image/png
  def presign_image(conn, params) do
    user = conn.assigns.current_user

    content_type =
      Map.get(params, "content_type") ||
        get_in(params, ["image", "content_type"]) ||
        "image/jpeg"

    # Determine extensions safely based on the mime type parameters
    extension =
      case content_type do
        "image/png" -> ".png"
        "image/webp" -> ".webp"
        "image/gif" -> ".gif"
        _ -> ".jpg"
      end

    # Structure folder hierarchy: proposal_comments/USER_ID/timestamp.ext
    file_key =
      "proposal_comments/#{user.id}/img_#{System.system_time(:second)}_#{System.unique_integer([:positive])}#{extension}"

    # Browser PUTs must go through the same-origin /media proxy (see MediaProxyController).
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      upload_url: "/media/#{file_key}",
      final_asset_url: "#{Kollective.Storage.cdn_domain()}/#{file_key}"
    })
  end

  # ─── INTERNAL PIPELINE ───

  defp insert_comment(conn, proposal, params) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    raw_params = Map.get(params, "comment") || params
    content_text = Map.get(raw_params, "content") || Map.get(raw_params, "text") || ""
    parent_id = Map.get(raw_params, "parent_id") || Map.get(raw_params, "parentId")
    comment_params = Map.put(raw_params, "content", content_text)

    # 1. EVALUATE CONTENT: run text inputs through the 5-priority moderation matrix
    case Moderation.determine_status(user, comment_params) do
      {:error, :forbidden_content, matched_word} ->
        # TWO-STRIKE HARD-BAN TRIGGER SYSTEM
        Moderation.track_denied_word(user.id, matched_word)

        case Moderation.record_denial(user.id) do
          :cooldown ->
            triggered_words = Moderation.get_denied_words(user.id)

            Security.blacklist_ip_temporary(ip, :timer.hours(1))

            Accounts.flag_user_for_spam("user:#{user.id}")

            enqueue_security_alert(
              "cooldown_triggered",
              user.id,
              ip,
              2,
              "Triggered words: #{triggered_words}"
            )

            # Trick the bot with a fake success code
            json(conn, %{status: "success", message: "Comment queued for review."})

          :ok ->
            enqueue_security_alert(
              "hard_ban_attempt",
              user.id,
              ip,
              1,
              "Triggered word: #{matched_word}"
            )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Your comment contains prohibited language."})
        end

      {:ok, status} ->
        # 2. NORMAL CREATION PIPELINE
        db_status =
          case status do
            :published -> "approved"
            other -> Atom.to_string(other)
          end

        final_params =
          %{
            "business_id" => proposal.id,
            "user_id" => user.id,
            "content" => content_text,
            "moderation_status" => db_status
          }
          |> Map.put_new("parent_id", parent_id)
          |> Map.put_new(
            "image_url",
            Map.get(raw_params, "image_url") || Map.get(raw_params, "imageUrl")
          )

        case Businesses.create_proposal_comment(final_params) do
          {:ok, comment} ->
            hydrated_comment = Repo.preload(comment, [:user])

            # 3. TRIGGER TEXT MENTIONS AND IMAGE SCANS IN THE BACKGROUND VIA OBAN
            %{"comment_id" => hydrated_comment.id}
            |> Kollective.Workers.CommentMentionsWorker.new()
            |> Oban.insert()

            if final_params["image_url"], do: enqueue_image_moderation_worker(hydrated_comment)

            # 4. DISPATCH THE REAL-TIME PUBSUB FRAME DOWNSTREAM
            Phoenix.PubSub.broadcast(
              Kollective.PubSub,
              "proposal:#{proposal.id}",
              {"new_comment",
               %{comment: hydrated_comment, author_shadow_banned?: user.is_shadow_banned}}
            )

            conn
            |> put_status(:created)
            |> json(%{status: "success", data: ProposalCommentJSON.data(hydrated_comment)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Failed to create comment.",
              details: ChangesetJSON.error(%{changeset: changeset})
            })
        end
    end
  end

  defp fetch_proposal(proposal_id) do
    {:ok, Businesses.get_business_by_type!(proposal_id, "proposals")}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    ArgumentError -> {:error, :not_found}
  end

  # 🔒 SERVER-SIDE STATE BOUNDARY: the discussion belongs to the proposal's state.
  defp authorize_state(conn, %Business{} = proposal, _mode) do
    if StateGate.locked?(Businesses.proposal_state_code(proposal), actor_state(conn)) do
      {:error, :locked}
    else
      :ok
    end
  end

  defp actor_state(conn) do
    case conn.assigns[:current_user] do
      nil -> nil
      user -> Map.get(user, :state)
    end
  end

  defp guest_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp enqueue_security_alert(type, uid, ip, strikes, notes) do
    %{"type" => type, "user_id" => uid, "ip" => ip, "strikes" => strikes, "notes" => notes}
    |> Kollective.Workers.SecurityAlertWorker.new()
    |> Oban.insert!()
  end

  defp enqueue_image_moderation_worker(c) do
    %{"comment_id" => c.id, "image_url" => c.image_url}
    |> Kollective.Workers.ImageModerationWorker.new()
    |> Oban.insert!()
  end
end

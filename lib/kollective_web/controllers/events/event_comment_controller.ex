defmodule KollectiveWeb.EventCommentController do
  use KollectiveWeb, :controller
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events
  alias Kollective.Moderation.Moderation
  alias Kollective.Security.Security
  alias KollectiveWeb.{ChangesetJSON, CommentJSON}

  # Throttle the endpoint to protect the database from script flooding
  plug KollectiveWeb.Plugs.RateLimiter when action in [:create]

  # GET /api/v1/event_comments (Scoped via Query params, e.g. ?event_id=01J0A...&cursor=01J0B...)
  def index(conn, %{"event_id" => event_id} = params) do
    current_user = conn.assigns[:current_user]

    # Fetch top-level thread nodes with batch hydration counters populated instantly
    comments = Events.list_event_comments(event_id, current_user, params)

    # Establish look-ahead cursor pagination logic for endless scroll triggers
    next_cursor = if comments != [], do: List.last(comments).id, else: nil

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: CommentJSON.index(%{comments: comments}),
      next_cursor: to_string(next_cursor)
    })
  end

  # GET /api/v1/event_comments/:id
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Events.get_comment(id, current_user) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Comment not found or access is restricted."})

      {:ok, comment} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: CommentJSON.data(comment)
        })
    end
  end

  # POST /api/v1/events_comments/:event_id/comment
  def create(conn, %{"event_id" => event_id} = params) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    raw_params = Map.get(params, "comment") || params
    content_text = Map.get(raw_params, "content") || Map.get(raw_params, "text") || ""
    parent_id = Map.get(raw_params, "parent_id") || Map.get(raw_params, "parentId")
    comment_params = Map.put(raw_params, "content", content_text)

    # 1. EVALUATE CONTENT: Run text inputs directly through your 5-priority matrix
    case Moderation.determine_status(user, comment_params) do
      {:error, :forbidden_content, matched_word} ->
        # TWO-STRIKE HARD-BAN TRIGGER SYSTEM
        Moderation.track_denied_word(user.id, matched_word)

        case Moderation.record_denial(user.id) do
          :cooldown ->
            triggered_words = Moderation.get_denied_words(user.id)

            Security.blacklist_ip_temporary(
              ip,
              :timer.hours(1)
            )

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
        # Inject the soft-ban status into attributes ("approved" or "pending")
        db_status =
          case status do
            :published -> "approved"
            other -> Atom.to_string(other)
          end

        final_params =
          %{
            "event_id" => event_id,
            "user_id" => user.id,
            "content" => content_text,
            "moderation_status" => db_status
          }
          |> Map.put_new("parent_id", parent_id)
          |> Map.put_new(
            "image_url",
            Map.get(raw_params, "image_url") || Map.get(raw_params, "imageUrl")
          )

        case Events.create_comment(final_params) do
          {:ok, comment} ->
            hydrated_comment = Repo.preload(comment, [:user])

            # 3. TRIGGER TEXT MENTIONS AND IMAGES SCANS IN THE BACKGROUND VIA OBAN
            # Task.start(fn -> Events.process_comment_mentions(hydrated_comment) end)
            %{"comment_id" => hydrated_comment.id}
            |> Kollective.Workers.CommentMentionsWorker.new()
            |> Oban.insert()

            if final_params["image_url"], do: enqueue_image_moderation_worker(hydrated_comment)

            # 4. DISPATCH THE REAL-TIME PUBSUB FRAME DOWNSTREAM
            # We flag if the author is shadow-banned so our FeedChannel interceptor can isolate it safely
            Phoenix.PubSub.broadcast(
              Kollective.PubSub,
              "event:#{event_id}",
              {"new_comment",
               %{comment: hydrated_comment, author_shadow_banned?: user.is_shadow_banned}}
            )

            conn
            |> put_status(:created)
            |> json(%{status: "success", data: CommentJSON.data(hydrated_comment)})

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

  # --- Structural Helpers ---
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

  # POST /api/v1/event_comments/:comment_id/like
  def like(conn, %{"comment_id" => comment_id}) do
    user = conn.assigns.current_user

    case Events.like_comment(user.id, comment_id) do
      {:ok, {:ok, :liked}} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Comment liked successfully."})

      {:error, :already_liked} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "already_liked", message: "You have already liked this comment."})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "operation_failed"})
    end
  end

  # GET /api/v1/event_comments/image/presign
  # Expected params: ?content_type=image/png
  def presign_image(conn, %{"content_type" => content_type}) do
    user = conn.assigns.current_user

    # Determine extensions safely based on the mime type parameters
    extension =
      case content_type do
        "image/png" -> ".png"
        "image/webp" -> ".webp"
        _ -> ".jpg"
      end

    # Structure folder hierarchy: comments/USER_ID/timestamp.ext
    file_key = "comments/#{user.id}/img_#{System.system_time(:second)}#{extension}"

    # Browser PUTs must go through the same-origin /media proxy. A direct
    # presigned PUT to *.r2.cloudflarestorage.com fails CORS preflight (403),
    # and that endpoint is not a public CDN for <img src>. The proxy writes
    # to R2 server-side via MediaProxyController.upload/2.
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      upload_url: "/media/#{file_key}",
      final_asset_url: "#{Kollective.Storage.cdn_domain()}/#{file_key}"
    })
  end
end

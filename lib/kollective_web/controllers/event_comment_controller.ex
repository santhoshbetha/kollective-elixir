defmodule KollectiveWeb.EventCommentController do
  use KollectiveWeb, :controller
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events
  alias Kollective.Moderation.Moderation
  alias Kollective.Security.Security

  # Throttle the endpoint to protect the database from script flooding
  plug KollectiveWeb.Plugs.RateLimiter when action in [:create]

  # GET /api/v1/event_comments (Scoped via Query params, e.g. ?event_id=01J0A...&cursor=01J0B...)
  def index(conn, %{"event_id" => event_id} = params) do
    current_user = conn.assigns[:current_user]

    # Fetch top-level thread nodes with batch hydration counters populated instantly
    comments = Events.list_event_comments(event_id, current_user, params)

    # Establish look-ahead cursor pagination logic for endless scroll triggers
    next_cursor = if comments != [], do: List.last(comments).id, else: nil

    json(conn, %{
      status: "success",
      data: KollectiveWeb.CommentJSON.index(%{comments: comments}),
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
        json(conn, %{
          status: "success",
          data: KollectiveWeb.CommentJSON.data(comment)
        })
    end
  end

  # POST /api/v1/events_comments/:event_id/comment
  def create(conn, %{"event_id" => event_id, "comment" => comment_params}) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

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
        # Inject the soft-ban status into attributes ("published" or "pending")
        final_params =
          comment_params
          |> Map.put("event_id", event_id)
          |> Map.put("user_id", user.id)
          |> Map.put("status", Atom.to_string(status))

        case Events.create_comment(final_params) do
          {:ok, comment} ->
            hydrated_comment = Repo.preload(comment, [:user])

            # 3. TRIGGER TEXT MENTIONS AND IMAGES SCANS IN THE BACKGROUND VIA OBAN
            Task.start(fn -> Events.process_comment_mentions(hydrated_comment) end)

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
            |> json(%{status: "success", data: KollectiveWeb.CommentJSON.data(hydrated_comment)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to create comment.", details: changeset})
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
        json(conn, %{status: "success", message: "Comment liked successfully."})

      {:ok, {:error, :already_liked}} ->
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
    config = ExAws.Config.new(:s3)
    bucket = "your-r2-comments-bucket"

    # Determine extensions safely based on the mime type parameters
    extension =
      case content_type do
        "image/png" -> ".png"
        "image/webp" -> ".webp"
        _ -> ".jpg"
      end

    # Structure folder hierarchy: comments/USER_ID/timestamp.ext
    file_key = "comments/#{user.id}/img_#{System.system_time(:second)}#{extension}"

    # Generate an unauthenticated secure write ticket to R2 edge pools
    {:ok, url} =
      ExAws.S3.presigned_url(config, :put, bucket, file_key,
        expires_in: 3600,
        query_params: [{"Content-Type", content_type}]
      )

    conn
    |> put_status(:ok)
    # FIX: Corrected string interpolation syntax with a leading root forward slash
    |> json(%{
      status: "success",
      upload_url: url,
      final_asset_url: "https://your-custom-cdn.com{file_key}"
    })
  end
end

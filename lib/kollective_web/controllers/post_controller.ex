defmodule KollectiveWeb.PostController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post
  alias Kollective.Moderation.Moderation
  alias Kollective.Accounts.Accounts
  alias Kollective.Security.Security
  alias Kollective.Notifications.Notifications
  alias KollectiveWeb.PostJSON

  # GET /api/v1/posts
  # Accessible options via query string: ?category=voice&scope=local&sort=top&cursor=432
  def index(conn, params) do
    # e.g., Request hits: /api/v1/posts?scope=state&category=voice&cursor=891
    current_user = conn.assigns.current_user

    # Call the fully unified, paginated, and geofenced engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts_for_feed(current_user, params)

    json(conn, %{
      # Modern Phoenix 1.7 standard: Pass items straight to your PostJSON collection index view
      data: PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end

  # POST /api/v1/posts
  def create(conn, %{"post" => post_params}) do
    user = conn.assigns.current_user
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    # 1. Identity Override Detection Gateway
    posting_author =
      case post_params["override_author_id"] do
        nil ->
          user

        override_id ->
          # Verify the user actually has approved permissions for this account
          is_allowed? =
            Kollective.Repo.exists?(
              from(m in "organization_memberships",
                where:
                  m.organization_id == ^override_id and m.user_id == ^user.id and
                    m.state == "approved"
              )
            )

          if is_allowed?, do: Accounts.get_user!(override_id), else: user
      end

    # 2. Evaluate content against the unified moderation matrix
    case Moderation.determine_status(posting_author, post_params) do
      {:error, :forbidden_content, matched_word} ->
        # 2. ESCALATION LAYER: Record a hard strike against this IP address instantly in RAM
        if Kollective.Security.Security.record_hard_strike(ip) do
          # Strike 2 Triggered! The bot is now blacklisted.
          # Fire off an high-urgency security alarm and throw a fake success packet (The Black Hole)
          enqueue_security_alert(
            "hard_ban_blacklist_banned",
            user.id,
            ip,
            2,
            "Triggered word: #{matched_word}"
          )

          conn
          |> put_status(:created)
          |> json(%{status: "success", message: "Post successfully queued for system delivery."})
        else
          # Strike 1 Triggered: Pass a user-friendly warning error toast
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error:
              "Your post contains prohibited language. Continuing to spam this content will result in an IP ban."
          })
        end

      # {:error, :forbidden_content, error_msg} ->
      # HARD REJECTION: Drop the request instantly and return an explicit validation message
      # conn
      # |> put_status(:unprocessable_entity)
      # |> json(%{errors: %{content: [error_msg]}})

      {:ok, status} ->
        # SOFT PASS / CLEAN: Inject the returned status (:published or :pending) into params
        post_params = Map.put(post_params, "status", Atom.to_string(status))

        # 2. DYNAMIC PIPELINE ROUTING ENGINE
        # Check if the incoming request specifies a voice layout
        execution_result =
          if post_params["category"] == "voice" do
            # Pull the chosen expiration length from the parameters string (defaults to :none)
            expiry_setting = Map.get(post_params, "expiry_type", "none")
            Posts.create_voice_post(posting_author, post_params, expiry: expiry_setting)
          else
            Posts.create_post(posting_author, post_params)
          end

        # 3. Handle pipeline output delivery
        case execution_result do
          {:ok, post} ->
            conn
            |> put_status(:created)
            |> json(%{status: "ok", data: PostJSON.show(post)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{status: "error", errors: KollectiveWeb.ChangesetJSON.error(changeset)})
        end
    end
  end

  # GET /api/v1/posts/:id
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]
    current_user_id = if current_user, do: current_user.id, else: nil

    # Call your newly optimized context lookup engine
    case Posts.get_post(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      {:ok, post} ->
        # Enforce visibility and accessibility guards
        if has_access_to_post?(post, current_user_id) do
          # Pass to the O(1) batch hydration layer to color heart/bookmark icons
          [hydrated_item] = Posts.hydrate_virtual_fields([post], current_user)

          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            data: KollectiveWeb.PostJSON.show(hydrated_item)
          })
        else
          # Return a 404 to protect the privacy of the account holder (Stealth Defense)
          conn |> put_status(:not_found) |> json(%{error: "Post not found"}) |> halt()
        end
    end
  end

  # --- Private Accessibility Rule Interceptors ---
  defp has_access_to_post?(%Post{visibility: "public"}, _), do: true
  defp has_access_to_post?(%Post{visibility: "unlisted"}, _), do: true

  defp has_access_to_post?(%Post{visibility: "private"} = post, current_user_id) do
    cond do
      # Author always has access to their own private content
      is_nil(current_user_id) -> false
      post.user_id == current_user_id -> true
      # Check if the active viewer follows the author
      true -> Accounts.following?(current_user_id, post.user_id)
    end
  end

  defp has_access_to_post?(%Post{visibility: "direct"} = post, current_user_id) do
    cond do
      is_nil(current_user_id) ->
        false

      post.user_id == current_user_id ->
        true

      # Check if the viewer's ID is pre-calculated inside our fast JSONB mentions cache array
      true ->
        Enum.any?(post.mentions || [], fn mention -> mention["id"] == current_user_id end)
    end
  end

  def index3(conn, _params) do
    # Your default list
    posts = Posts.list_posts_as_tree()

    conn
    |> put_status(:ok)
    |> json(%{status: "success", data: KollectiveWeb.PostJSON.index(%{entries: posts})})
  end

  # POST /api/posts/:id/like
  def handle_like(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_like(post_id, user.id) do
      {:ok, :liked} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", count: Posts.get_like_count(post_id), has_liked: true})

      {:ok, :unliked} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", count: Posts.get_like_count(post_id), has_liked: false})

      {:error, _reason} ->
        # Always handle the error fallback path to prevent 500 errors
        send_resp(conn, 422, "Unable to process request")
    end
  end

  # POST /api/v1/posts/:id/reblog
  def handle_reblog(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    # Execute the atomic social toggle block in your context layer
    case Posts.reblog_post(user.id, post_id) do
      {:ok, :reblogged, reblog_struct} ->
        # 1. SUCCESS TIER A: Post successfully boosted
        # Preload author and attachments for your uniform JSON layout contract
        hydrated_post = Kollective.Repo.preload(reblog_struct, [:author, :attachments])
        [hydrated_item] = Posts.hydrate_virtual_fields([hydrated_post], user)

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          action: "reblogged",
          # Return the complete serialized card to replace state arrays in React atomically
          data: KollectiveWeb.PostJSON.show(hydrated_item)
        })

      {:ok, :unreblogged} ->
        # 2. SUCCESS TIER B: Boost successfully retracted (undone)
        # Fetch the original post to return updated count metrics cleanly
        original_post =
          Posts.get_post!(post_id) |> Kollective.Repo.preload([:author, :attachments])

        [hydrated_item] = Posts.hydrate_virtual_fields([original_post], user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          action: "unreblogged",
          data: KollectiveWeb.PostJSON.show(hydrated_item)
        })

      {:error, :self_reblog_not_allowed} ->
        # 3. SAFETY CONTROLS: Rejection block shielding self-referencing actions
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "You cannot reblog your own post."})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Something went wrong processing your request."})
    end
  end

  # POST /api/v1/posts/:id/replies
  def create_reply(conn, %{"id" => parent_id, "post" => post_params}) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    # 1. Locate the target parent post first to verify existence and preload assets
    case Repo.get(Post, parent_id) |> Repo.preload([:author]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "The post you are trying to reply to does not exist."})

      parent_post ->
        # 2. CONTENT AUDITING GATES: Run the reply text through your master priority matrix
        case Moderation.determine_status(user, post_params) do
          {:error, :forbidden_content, matched_word} ->
            # ENFORCE TWO-STRIKE BLACKLIST SHIELD COOLDOWN
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
                  "Triggered reply words: #{triggered_words}"
                )

                # Trick the bot with fake success codes
                json(conn, %{
                  status: "success",
                  message: "Post successfully queued for system delivery."
                })

              :ok ->
                enqueue_security_alert(
                  "hard_ban_attempt",
                  user.id,
                  ip,
                  1,
                  "Triggered reply word: #{matched_word}"
                )

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Your reply contains prohibited language."})
            end

          {:ok, status} ->
            # 3. NORMAL PROCESSING PIPELINE
            status_str = Atom.to_string(status)
            final_params = Map.put(post_params, "status", status_str)

            case Posts.create_reply(user, parent_post, final_params) do
              {:ok, reply} ->
                # Preload core dependencies to fulfill your strict PostJSON rendering layout contract
                hydrated_reply = Repo.preload(reply, [:author, :attachments])
                [hydrated_item] = Posts.hydrate_virtual_fields([hydrated_reply], user)

                # 4. DISPATCH REAL-TIME WEBSOCKET PUSHES DOWNSTREAM
                # Broadcast to the thread details room channel to append the comment on active screens live
                Phoenix.PubSub.broadcast(
                  Kollective.PubSub,
                  "post_details:#{parent_post.root_post_id || parent_post.id}",
                  {"new_reply",
                   %{reply: hydrated_reply, author_shadow_banned?: user.is_shadow_banned}}
                )

                # Also alert the parent author securely via the ThreadMute protected notification engine
                Task.start(fn ->
                  Notifications.notify_reply(parent_post.user_id, user.id, hydrated_reply)
                end)

                conn
                |> put_status(:created)
                |> json(%{
                  status: "success",
                  data: KollectiveWeb.PostJSON.show(hydrated_item)
                })

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{status: "error", errors: KollectiveWeb.ChangesetJSON.error(changeset)})
            end
        end
    end
  end

  # --- Controller Private Helpers ---
  defp guest_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp enqueue_security_alert(type, uid, ip, strikes, notes) do
    %{"type" => type, "user_id" => uid, "ip" => ip, "strikes" => strikes, "notes" => notes}
    |> Kollective.Workers.SecurityAlertWorker.new()
    |> Oban.insert!()
  end

  # /api/posts?tag=elixir
  # def index2(conn, %{"tag" => tag_name}) do
  #  posts = Posts.list_posts_by_tag(tag_name)
  #  render(conn, :index, posts: posts)
  # end
end

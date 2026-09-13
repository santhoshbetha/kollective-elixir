defmodule KollectiveWeb.PostController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post
  alias Kollective.Moderation.Moderation
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership
  alias Kollective.Security.Security
  alias KollectiveWeb.PostJSON
  alias KollectiveWeb.ChangesetJSON

  # GET /api/v1/posts
  # Accessible options via query string: ?category=voice&scope=local&sort=top&cursor=432
  def index(conn, params) do
    # e.g., Request hits: /api/v1/posts?scope=state&category=voice&cursor=891
    current_user = conn.assigns.current_user

    # Call the fully unified, paginated, and geofenced engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts_for_feed(current_user, params)

    conn
    |> put_status(:ok)
    |> json(%{
      # Modern Phoenix 1.7 standard: Pass items straight to your PostJSON collection index view
      data: PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end

  # POST /api/v1/posts
  def create(conn, %{"post" => post_params} = params) do
    user = conn.assigns.current_user
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    # 1. Organization / Identity Context Gateway
    org_id = post_params["organization_id"] || post_params["override_author_id"]

    {authorized?, final_org_id} =
      cond do
        is_nil(org_id) or org_id == "" ->
          if user.type == :organization do
            {true, user.id}
          else
            {true, nil}
          end

        org_id == user.id ->
          {true, user.id}

        true ->
          is_member? =
            Repo.exists?(
              from(m in OrganizationMembership,
                where:
                  m.organization_id == ^org_id and m.user_id == ^user.id and
                    m.status == :approved
              )
            )

          {is_member?, org_id}
      end

    cond do
      not authorized? ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "forbidden",
          message: "You are not an approved member of this organization."
        })

      true ->
        posting_author = user
        post_params = Map.put(post_params, "organization_id", final_org_id)

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
              |> json(%{
                status: "success",
                message: "Post successfully queued for system delivery."
              })
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
            post_params =
              post_params
              |> Map.put("status", Atom.to_string(status))
              |> Map.put_new("poll", params["poll"])

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
                |> json(%{status: "error", errors: ChangesetJSON.error(changeset)})
            end
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
            data: PostJSON.show(hydrated_item)
          })
        else
          # Return a 404 to protect the privacy of the account holder (Stealth Defense)
          conn |> put_status(:not_found) |> json(%{error: "Post not found"}) |> halt()
        end
    end
  end

  # PUT /api/v1/posts/:id
  def update(conn, %{"id" => id, "post" => post_params}) do
    user = conn.assigns.current_user

    case Posts.get_post(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      {:ok, post} ->
        can_edit? =
          cond do
            not is_nil(post.user_id) and post.user_id == user.id ->
              true

            post.organization_id ->
              Repo.exists?(
                from(m in OrganizationMembership,
                  where:
                    m.organization_id == ^post.organization_id and
                      m.user_id == ^user.id and
                      m.role in [:admin, :owner] and
                      m.status == :approved
                )
              )

            true ->
              false
          end

        if not can_edit? do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "forbidden", message: "You are not authorized to edit this post."})
        else
          case Moderation.determine_status(user, post_params) do
            {:error, :forbidden_content, _matched_word} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Your updated post contains prohibited language."})

            {:ok, _status} ->
              case Posts.update_post(post, Map.put(post_params, "actor_id", user.id)) do
                {:ok, updated_post} ->
                  [hydrated_item] = Posts.hydrate_virtual_fields([updated_post], user)

                  conn
                  |> put_status(:ok)
                  |> json(%{status: "success", data: PostJSON.show(hydrated_item)})

                {:error, :poll_locked_by_votes} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Cannot modify poll options after voting has started."})

                {:error, %Ecto.Changeset{} = changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{
                    status: "error",
                    errors: ChangesetJSON.error(changeset)
                  })
              end
          end
        end
    end
  end

  # DELETE /api/v1/posts/:id
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Posts.get_post(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      {:ok, post} ->
        can_delete? =
          cond do
            not is_nil(post.user_id) and post.user_id == user.id ->
              true

            post.organization_id ->
              Repo.exists?(
                from(m in OrganizationMembership,
                  where:
                    m.organization_id == ^post.organization_id and
                      m.user_id == ^user.id and
                      m.role in [:admin, :owner] and
                      m.status == :approved
                )
              )

            true ->
              false
          end

        if not can_delete? do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "forbidden", message: "You are not authorized to delete this post."})
        else
          case Posts.delete_post(post, actor_id: user.id) do
            {:ok, _deleted_post} ->
              send_resp(conn, :no_content, "")

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{status: "error", errors: ChangesetJSON.error(changeset)})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: to_string(reason)})
          end
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
      not is_nil(post.user_id) and post.user_id == current_user_id -> true
      # Check if the active viewer follows the author
      is_nil(post.user_id) -> false
      true -> Accounts.following?(current_user_id, post.user_id)
    end
  end

  defp has_access_to_post?(%Post{visibility: "direct"} = post, current_user_id) do
    cond do
      is_nil(current_user_id) ->
        false

      not is_nil(post.user_id) and post.user_id == current_user_id ->
        true

      # Check if the viewer's ID is pre-calculated inside our fast JSONB mentions cache array
      true ->
        Enum.any?(post.mentions || [], fn mention ->
          (Map.get(mention, :id) || Map.get(mention, "id")) == current_user_id
        end)
    end
  end

  def index3(conn, _params) do
    # Your default list
    posts = Posts.list_posts_as_tree()

    conn
    |> put_status(:ok)
    |> json(%{status: "success", data: PostJSON.index(%{entries: posts})})
  end

  # POST /api/posts/:id/like
  def handle_like(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_like(user.id, post_id) do
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
          data: PostJSON.show(hydrated_item)
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
          data: PostJSON.show(hydrated_item)
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
                conn
                |> put_status(:created)
                |> json(%{
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

                if parent_post.user_id && parent_post.user_id != user.id do
                  %{
                    "recipient_id" => parent_post.user_id,
                    "actor_id" => user.id,
                    "reply_id" => hydrated_reply.id
                  }
                  |> Kollective.Workers.ReplyNotificationWorker.new()
                  |> Oban.insert()
                end

                conn
                |> put_status(:created)
                |> json(%{
                  status: "success",
                  data: PostJSON.show(hydrated_item)
                })

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{status: "error", errors: ChangesetJSON.error(changeset)})
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
end

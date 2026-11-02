defmodule KollectiveWeb.PostController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post
  alias Kollective.Moderation.Moderation
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership
  alias KollectiveWeb.PostJSON
  alias KollectiveWeb.AccountJSON
  alias KollectiveWeb.ChangesetJSON
  alias KollectiveWeb.Plugs.AuthorizeOrgSocialAction

  plug AuthorizeOrgSocialAction when action in [:handle_like, :handle_reblog]

  # GET /api/v1/posts
  # Accessible options via query string: ?category=voice&scope=local&sort=top&cursor=432
  def index(conn, params) do
    # e.g., Request hits: /api/v1/posts?scope=state&category=voice&cursor=891
    current_user = conn.assigns.current_user

    # Call the fully unified, paginated, and geofenced engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts_for_feed(current_user, params)

    serialized_posts = PostJSON.index(%{entries: entries})

    conn
    |> put_status(:ok)
    |> json(%{
      # Modern Phoenix 1.7 standard: Pass items straight to your PostJSON collection index view
      data: serialized_posts,
      posts: serialized_posts,
      next_cursor: next_cursor
    })
  end

  # POST /api/v1/posts
  def create(conn, %{"post" => post_params} = params) do
    user = conn.assigns.current_user
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    do_create(conn, user, ip, post_params, params)
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    do_create(conn, user, ip, params, params)
  end

  defp do_create(conn, user, ip, post_params, params) do
    # Normalize content and text attributes
    content_text = post_params["content"] || post_params["text"] || ""

    # Normalize category: "Voices" / "voice" -> "voice", else "post"
    raw_category = post_params["category"] || if post_params["isVoice"], do: "voice", else: "post"

    category =
      case to_string(raw_category || "") |> String.downcase() do
        "voice" -> "voice"
        "voices" -> "voice"
        _ -> "post"
      end

    # Normalize audience / target_scope
    raw_audience = post_params["target_scope"] || post_params["audience"] || "world"

    target_scope =
      case to_string(raw_audience || "") |> String.downcase() do
        s when s in ["local", "my_location"] -> "local"
        "state" -> "state"
        s when s in ["country", "national"] -> "country"
        _ -> "world"
      end

    focal_x = post_params["focal_x"] || params["focal_x"] || get_in(post_params, ["meta", "focus", "x"]) || get_in(params, ["meta", "focus", "x"])
    focal_y = post_params["focal_y"] || params["focal_y"] || get_in(post_params, ["meta", "focus", "y"]) || get_in(params, ["meta", "focus", "y"])
    spoiler_text = post_params["spoiler_text"] || post_params["content_warning"] || params["spoiler_text"] || params["content_warning"]

    post_params =
      post_params
      |> Map.put("content", content_text)
      |> Map.put("text", content_text)
      |> Map.put("category", category)
      |> Map.put("target_scope", target_scope)
      |> Map.put_new(
        "visibility",
        if(raw_audience == "Followers Only", do: "private", else: "public")
      )
      |> then(fn p -> if focal_x != nil, do: Map.put(p, "focal_x", focal_x), else: p end)
      |> then(fn p -> if focal_y != nil, do: Map.put(p, "focal_y", focal_y), else: p end)
      |> then(fn p -> if spoiler_text != nil, do: Map.put(p, "spoiler_text", spoiler_text), else: p end)
      |> Map.put_new("media_attachments", params["media_attachments"])
      |> Map.put_new("media_ids", params["media_ids"])
      |> Map.put_new("images", params["images"])
      |> then(fn p ->
        preview = p["preview_card"] || p["link_preview"] || params["preview_card"] || params["link_preview"]
        if is_map(preview) do
          p
          |> Map.put_new("link_url", preview["url"] || preview[:url])
          |> Map.put_new("link_title", preview["title"] || preview[:title])
          |> Map.put_new("link_description", preview["description"] || preview[:description])
          |> Map.put_new("link_preview_image", preview["image_url"] || preview[:image_url] || preview["image"] || preview[:image])
        else
          p
        end
      end)

    # 1. Organization / Identity Context Gateway
    org_id =
      post_params["organization_id"] ||
        post_params["override_author_id"] ||
        (conn.assigns[:current_organization] && conn.assigns[:current_organization].id)

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

        conn.assigns[:current_organization] && conn.assigns[:current_organization].id == org_id ->
          {true, org_id}

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

            IO.inspect(post_params, label: "POST_CONTROLLER INCOMING PARAMS")

            # 3. Handle pipeline output delivery
            case execution_result do
              {:ok, post} ->
                conn
                |> put_status(:created)
                |> json(%{status: "ok", data: PostJSON.show(post)})

              {:error, %Ecto.Changeset{} = changeset} ->
                errors_map =
                  Ecto.Changeset.traverse_errors(
                    changeset,
                    &KollectiveWeb.ChangesetJSON.translate_error/1
                  )

                error_msg =
                  Enum.map_join(errors_map, "; ", fn {field, msgs} ->
                    "#{field}: #{Enum.join(List.wrap(msgs), ", ")}"
                  end)

                IO.inspect(errors_map, label: "POST_CONTROLLER VALIDATION ERRORS")

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{
                  status: "error",
                  message: error_msg,
                  error: error_msg,
                  errors: errors_map
                })

              {:error, reason} ->
                error_msg = inspect(reason)
                IO.inspect(reason, label: "POST_CONTROLLER OTHER ERROR")

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{
                  status: "error",
                  message: error_msg,
                  error: error_msg
                })
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
        cond do
          current_user && post.author && Accounts.blocks?(post.author, current_user) ->
            conn
            |> put_status(:forbidden)
            |> json(%{
              error: "blocked",
              message: "You are blocked from viewing this resource."
            })

          # Enforce visibility and accessibility guards
          has_access_to_post?(post, current_user_id) ->
            # Pass to the O(1) batch hydration layer to color heart/bookmark icons
            [hydrated_item] = Posts.hydrate_virtual_fields([post], current_user)

            conn
            |> put_status(:ok)
            |> json(%{
              status: "success",
              data: PostJSON.show(hydrated_item)
            })

          true ->
            # Return a 404 to protect the privacy of the account holder (Stealth Defense)
            conn |> put_status(:not_found) |> json(%{error: "Post not found"}) |> halt()
        end
    end
  end

  # GET /api/v1/posts/:id/context
  def context(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Posts.get_post_context(id, current_user) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Post not found"})

      {:ok, %{ancestors: ancestors, focus: focus, descendants: descendants}} ->
        focus_author = Map.get(focus, :author) || (Map.get(focus, :post) && Map.get(focus.post, :author))

        if current_user && focus_author && Accounts.blocks?(focus_author, current_user) do
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "blocked",
            message: "You are blocked from viewing this resource."
          })
        else
          conn
          |> put_status(:ok)
          |> json(%{
            ancestors: Enum.map(ancestors, &PostJSON.show/1),
            focus: PostJSON.show(focus),
            descendants: Enum.map(descendants, &PostJSON.show/1)
          })
        end
    end
  end

  # GET /api/v1/posts/:id/liked_by
  def liked_by(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Posts.get_post(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      {:ok, post} ->
        if has_access_to_post?(post, if(current_user, do: current_user.id, else: nil)) do
          users = Posts.list_liked_by_users(id)

          conn
          |> put_status(:ok)
          |> json(AccountJSON.index(%{users: users, for: current_user}))
        else
          conn |> put_status(:not_found) |> json(%{error: "Post not found"}) |> halt()
        end
    end
  end

  # GET /api/v1/posts/:id/reblogged_by
  def reblogged_by(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Posts.get_post(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      {:ok, post} ->
        if has_access_to_post?(post, if(current_user, do: current_user.id, else: nil)) do
          users = Posts.list_reblogged_by_users(id)

          conn
          |> put_status(:ok)
          |> json(AccountJSON.index(%{users: users, for: current_user}))
        else
          conn |> put_status(:not_found) |> json(%{error: "Post not found"}) |> halt()
        end
    end
  end

  # PUT /api/v1/posts/:id
  def update(conn, %{"id" => id, "post" => raw_post_params}) when is_map(raw_post_params) do
    user = conn.assigns.current_user

    post_params =
      raw_post_params
      |> then(fn p ->
        cond do
          Map.has_key?(p, "text") and not Map.has_key?(p, "content") ->
            Map.put(p, "content", p["text"])

          Map.has_key?(p, "content") and not Map.has_key?(p, "text") ->
            Map.put(p, "text", p["content"])

          true ->
            p
        end
      end)
      |> then(fn p ->
        sp = Map.get(raw_post_params, "spoiler_text") || Map.get(raw_post_params, "content_warning")
        if sp != nil, do: Map.put(p, "spoiler_text", sp), else: p
      end)

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

  def update(conn, %{"id" => id} = params) do
    post_params = Map.drop(params, ["id"])
    update(conn, %{"id" => id, "post" => post_params})
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
    actor_id =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization].id
      else
        conn.assigns.current_user.id
      end

    # 🚀 The controller now reads the count directly out of the context return tuple!
    case Posts.toggle_like(actor_id, post_id) do
      {:ok, :liked, updated_count} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          count: updated_count,
          has_liked: true
        })

      {:ok, :unliked, updated_count} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          count: updated_count,
          has_liked: false
        })

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", error: "Unable to process preference state toggle."})
    end
  end

  # POST /api/v1/posts/:id/reblog
  def handle_reblog(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    org_id =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization].id
      else
        nil
      end

    case Posts.reblog_post(user.id, post_id, org_id) do
      {:ok, :reblogged, reblog_struct} ->
        # Preload and hydrate the original target post so the returned card has updated reblogs_count
        original_post =
          Posts.get_post!(post_id)
          |> Kollective.Repo.preload([:author, :attachments, :hashtags, poll: :options])

        actor =
          if org_id, do: conn.assigns[:current_organization], else: user

        [hydrated_item] = Posts.hydrate_virtual_fields([original_post], actor)

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          action: "reblogged",
          data: PostJSON.show(hydrated_item),
          reblog: PostJSON.show(reblog_struct)
        })

      {:ok, :unreblogged} ->
        original_post =
          Posts.get_post!(post_id)
          |> Kollective.Repo.preload([:author, :attachments, :hashtags, poll: :options])

        actor =
          if org_id, do: conn.assigns[:current_organization], else: user

        [hydrated_item] = Posts.hydrate_virtual_fields([original_post], actor)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          action: "unreblogged",
          data: PostJSON.show(hydrated_item)
        })

      {:error, :self_reblog_not_allowed} ->
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
  # POST /api/v1/posts/:id/reply
  def create_replyX(conn, %{"id" => parent_id} = params) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    post_params = Map.get(params, "post", params)
    content_text = post_params["text"] || post_params["content"] || ""
    post_params = Map.put(post_params, "content", content_text)

    # 1. Locate the target parent post first to verify existence and preload assets
    case Repo.get(Post, parent_id) |> Repo.preload([:author]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "The post you are trying to reply to does not exist."})

      parent_post ->
        # Inherit category and target_scope from parent post if missing
        post_params =
          post_params
          |> Map.put_new("category", parent_post.category || "post")
          |> Map.put_new("target_scope", parent_post.target_scope || "local")

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

  # POST /api/v1/posts/:id/replies
  # POST /api/v1/posts/:id/reply
  def create_reply(conn, %{"id" => route_id} = params) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    post_params = Map.get(params, "post", params)
    content_text = post_params["text"] || post_params["content"] || ""
    post_params = Map.put(post_params, "content", content_text)

    # 🚀 THE ELIXIR PARAMETER FIX:
    # Check if an explicit "parent_id" was sent in the body JSON payload.
    # Fall back directly to the route_id parameter if a top-level focus post reply path is fired.
    target_parent_id =
      Map.get(params, "parent_id") || Map.get(post_params, "parent_id") || route_id

    # 1. Locate the target parent post first to verify existence and preload assets
    parent_lookup =
      case Ecto.ULID.cast(target_parent_id) do
        {:ok, valid_parent_id} -> Repo.get(Post, valid_parent_id) |> Repo.preload([:author])
        :error -> nil
      end

    case parent_lookup do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "The post you are trying to reply to does not exist."})

      parent_post ->
        # Inherit category and target_scope from parent post if missing
        post_params =
          post_params
          |> Map.put_new("category", parent_post.category || "post")
          |> Map.put_new("target_scope", parent_post.target_scope || "local")

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

            # Pass the dynamic sub-reply target block down into your database insertion layers
            case Posts.create_reply(user, parent_post, final_params) do
              {:ok, reply} ->
                # Preload core dependencies to fulfill your strict PostJSON rendering layout contract
                hydrated_reply = Repo.preload(reply, [:author, :attachments])
                [hydrated_item] = Posts.hydrate_virtual_fields([hydrated_reply], user)

                # 4. DISPATCH REAL-TIME WEBSOCKET PUSHES DOWNSTREAM
                # Broadcast to the thread details room channel to append the comment on active screens live
                # Tracks the thread via root_post_id fallback so deep replies stay inside the active view
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

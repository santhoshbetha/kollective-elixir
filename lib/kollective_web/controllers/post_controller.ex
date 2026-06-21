defmodule KollectiveWeb.PostController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post
  alias Kollective.Moderation.Moderation
  alias Kollective.Accounts.Accounts

  #action_fallback KollectiveWeb.FallbackController



  #fetch('/api/posts')
  #{
  #  "data": [
  #    {
  #      "id": 1,
  #      "body": "First post!",
  #      "replies": [
  #        {
  #          "id": 2,
  #          "body": "Reply to first post",
  #          "in_reply_to_id": 1,
  #          "replies": []
  #        }
  #      ]
  #    }
  #  ]
  #}
  def index2(conn, _params) do
    posts = Posts.list_posts_as_tree()
    render(conn, :index2, posts: posts)
  end

  # GET /api/v1/posts
  # Accessible options via query string: ?category=voice&scope=local&sort=top&cursor=432
  def index(conn, params) do
    # e.g., Request hits: /api/v1/posts?scope=state&category=voice&cursor=891
    current_user = conn.assigns.current_user

    # Call the fully unified, paginated, and geofenced engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts(current_user, params)

    json(conn, %{
      data: render_serialized_feed(entries),
      next_cursor: next_cursor
    })
  end

  defp render_serialized_feed(entries) do
    # Maps results instantly to your standard UI presentation viewports
    Enum.map(entries, fn item ->
      %{
        id: item.post.id,
        content: item.post.content,
        category: item.post.category,
        inserted_at: item.post.inserted_at,
        likes_count: item.likes_count,
        reblogs_count: item.reblogs_count,
        has_liked: item.has_liked,
        has_reblogged: item.has_reblogged,
        favourited: item.post.favourited,
        reblogged: item.post.reblogged,
        bookmarked: item.post.bookmarked,
        vote_data: item.post.vote_data,
        my_reactions: Map.get(item.post.data || %{}, "my_reactions", []),
        author: %{
          id: item.post.author.id,
          username: item.post.author.username,
          avatar_url: item.post.author.avatar_url
        }
      }
    end)
  end

  def create(conn, %{"post" => post_params}) do
    user = conn.assigns.current_user

    # 1. Evaluate content against the unified moderation matrix
    case Moderation.determine_status(user, post_params) do
      {:error, :forbidden_content, error_msg} ->
        # HARD REJECTION: Drop the request instantly and return an explicit validation message
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{content: [error_msg]}})

      {:ok, status} ->
        # SOFT PASS / CLEAN: Inject the returned status (:published or :pending) into params
        post_params = Map.put(post_params, "status", Atom.to_string(status))

        # 2. DYNAMIC PIPELINE ROUTING ENGINE
        # Check if the incoming request specifies a voice layout
        execution_result =
          if post_params["category"] == "voice" do
            # Pull the chosen expiration length from the parameters string (defaults to :none)
            expiry_setting = Map.get(post_params, "expiry_type", "none")
            Posts.create_voice_post(user, post_params, expiry: expiry_setting)
          else
            Posts.create_post(user, post_params)
          end

        # 3. Handle pipeline output delivery
        case execution_result do
          {:ok, post} ->
            conn
            |> put_status(:created)
            |> render(:show, post: post, current_user: user)
          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end


  #/api/posts?tag=elixir
  #def index2(conn, %{"tag" => tag_name}) do
  #  posts = Posts.list_posts_by_tag(tag_name)
  #  render(conn, :index, posts: posts)
  #end

  #GET /api/posts/:id
  def show(conn, %{"id" => id}) do
    # Support both authenticated users and anonymous public visitors safely
    current_user = conn.assigns[:current_user]
    current_user_id = if current_user, do: current_user.id, else: nil

    # 1. Fetch the target post (Preload author and mentions for fast guard checks)
    case Repo.get(Post, id) |> Repo.preload([:author]) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      post ->
        # 2. ENFORCE VISIBILITY ACCESSIBILITY GUARDS
        if has_access_to_post?(post, current_user_id) do
          # 3. Safe to fetch the flattened thread and convert it to a tree structure
          # Pass the current_user down so your batch hydration engine colors heart icons correctly
          thread_tree = Posts.get_context(post, current_user)

          render(conn, :thread, tree: thread_tree)
        else
          # Return a 404 to protect the privacy of the account holder
          conn
          |> put_status(:not_found)
          |> json(%{error: "Post not found or access is restricted."})
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
      is_nil(current_user_id) -> false
      post.user_id == current_user_id -> true

      # Check if the viewer's ID is pre-calculated inside our fast JSONB mentions cache array
      true ->
        Enum.any?(post.mentions || [], fn mention -> mention["id"] == current_user_id end)
    end
  end

  #def show(conn, %{"id" => id}) do
  #  post = Posts.get_post!(id)
  #  render(conn, :show2, post: post)
  #end

  def index3(conn, _params) do
    posts = Posts.list_posts_as_tree() # Your default list
    render(conn, :index, posts: posts)
  end

  # POST /api/posts/:id/like
  def handle_like(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_like(post_id, user.id) do
      {:ok, :liked} ->
        render(conn, :like_success, count: Posts.get_like_count(post_id), has_liked: true)

      {:ok, :unliked} ->
        render(conn, :like_success, count: Posts.get_like_count(post_id), has_liked: false)

      {:error, _reason} ->
        # Always handle the error fallback path to prevent 500 errors
        send_resp(conn, 422, "Unable to process request")
    end
  end

  # "POST /api/v1/posts/:id/reblog"
  def handle_reblog(conn, %{"id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.reblog_post(user.id, post_id) do
      {:ok, :reblogged, _reblog} ->
        # User successfully boosted the post
        render(conn, :reblog_success,
          count: Posts.get_reblog_count(post_id),
          has_reblogged: true
        )

      {:ok, :unreblogged} ->
        # User successfully undid their boost
        render(conn, :reblog_success,
          count: Posts.get_reblog_count(post_id),
          has_reblogged: false
        )

      {:error, :self_reblog_not_allowed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "You cannot reblog your own post"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Something went wrong processing your request"})
    end
  end

  # "POST /api/v1/posts/:id/replies"
  def create_reply(conn, %{"post_id" => parent_id, "post" => post_params}) do
    user = conn.assigns.current_user

    # 1. Locate the target parent post first to verify existence
    # Make sure to preload the author relations so usernames can be cached safely!
    case Repo.get(Post, parent_id) |> Repo.preload(:author) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "The post you are trying to reply to does not exist."})

      parent_post ->
        # 2. Hand off cleanly to your unified context function
        case Posts.create_reply(user, parent_post, post_params) do
          {:ok, reply} ->
            # Render the freshly created reply object back out to the React composer
            conn |> put_status(:created) |> render(:show2, post: reply)

          {:error, changeset} ->
            conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
        end
    end
  end


  #def update(conn, %{"id" => id, "post" => post_params}) do
  #  post = Posts.get_post!(id)
  #
  #  with {:ok, %Post{} = post} <- Posts.update_post(post, post_params) do
  #    render(conn, :show, post: post)
  #  end
  #end

  #def delete(conn, %{"id" => id}) do
  #  post = Posts.get_post!(id)
  #
  #  with {:ok, %Post{}} <- Posts.delete_post(post) do
  #    send_resp(conn, :no_content, "")
  #  end
  #end


end

defmodule KollectiveWeb.PostController do
  use KollectiveWeb, :controller

  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post

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
  def index(conn, _params) do
    posts = Posts.list_posts_as_tree()
    render(conn, :index2, posts: posts)
  end

  def create(conn, %{"post" => post_params}) do
    with {:ok, %Post{} = post} <- Posts.create_post(post_params) do
      # Broadcast ONLY the small metadata or ID to the public
      #KollectiveWeb.Endpoint.broadcast("feed:public", "new_post_available", %{
      #  id: post.id,
      #  author: post.author.username
      #})

      conn
      |> put_status(:created)
      |> render(:show2, post: post)
    end
  end

  #/api/posts?tag=elixir
  def index2(conn, %{"tag" => tag_name}) do
    posts = Posts.list_posts_by_tag(tag_name)
    render(conn, :index, posts: posts)
  end

  def index3(conn, _params) do
    posts = Posts.list_posts_as_tree() # Your default list
    render(conn, :index, posts: posts)
  end

  def handle_like(conn, %{"post_id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_like(post_id, user.id) do
      {:ok, _struct} ->
        # Return the new count to React
        render(conn, :like_success, count: Posts.get_like_count(post_id), has_liked: true)
      {:ok, %Ecto.Schema.Metadata{}} -> # Handle delete case
        render(conn, :like_success, count: Posts.get_like_count(post_id), has_liked: false)
    end
  end

  def toggle_reblog(conn, %{"post_id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.reblog_post(user.id, post_id) do
      {:ok, _result} ->
        # Return the new count to React
        render(conn, :reblog_success, count: Posts.get_reblog_count(post_id))

      {:error, :self_reblog_not_allowed} ->
        conn

        |> put_status(:unprocessable_entity)
        |> json(%{error: "You cannot boost your own post"})
    end
  end

  #GET /api/posts/:id
  def show(conn, %{"id" => id}) do
    #current_user_id = conn.assigns.current_user.id

    # 1. Fetch the target post first to get its schema struct
    case Kollective.Repo.get(Post, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Post not found"})

      post ->
        # 2. Fetch the entire flattened thread and convert it to a tree structure
        thread_tree = Posts.get_context(post)

        # 3. Render the nested tree structure to React
        render(conn, :thread, tree: thread_tree)
    end
  end



  #def show(conn, %{"id" => id}) do
  #  post = Posts.get_post!(id)
  #  render(conn, :show2, post: post)
  #end

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

# lib/kollective_web/controllers/posts/bookmark_controller.ex
defmodule KollectiveWeb.BookmarkController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts
  alias KollectiveWeb.PostJSON
  alias KollectiveWeb.ChangesetJSON

  # GET /api/v1/bookmarks
  # Supported params for endless scrolling loaders: ?limit=20&cursor=01J0A...
  def index(conn, params) do
    user = conn.assigns.current_user

    # Fetch preloaded post list maps in exactly one pass
    posts = Posts.list_bookmarked_posts(user, params)
    next_cursor = if posts != [], do: List.last(posts).bookmark_cursor_id, else: nil

    hydrated_posts = Posts.hydrate_virtual_fields(posts, user)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: PostJSON.index(hydrated_posts),
      next_cursor: to_string(next_cursor)
    })
  end

  # POST /api/v1/posts/:post_id/bookmark
  def toggle(conn, %{"post_id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_bookmark_post(user, post_id) do
      {:ok, :inserted} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          action: "inserted",
          message: "Post successfully bookmarked."
        })

      {:ok, :removed} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          action: "removed",
          message: "Bookmark successfully removed."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(changeset))
    end
  end

  # DELETE /api/v1/bookmarks/:bookmark_id
  # DELETE /api/v1/posts/:post_id/bookmark
  def delete(conn, %{"bookmark_id" => bookmark_id}) do
    user = conn.assigns.current_user

    case Posts.delete_bookmark_post(user, bookmark_id) do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          action: "deleted",
          message: "Bookmark successfully removed."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Bookmark not found."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(changeset))
    end
  end

  def delete(conn, %{"post_id" => post_id}) do
    delete(conn, %{"bookmark_id" => post_id})
  end
end

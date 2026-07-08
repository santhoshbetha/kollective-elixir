# lib/kollective_web/controllers/bookmark_controller.ex
defmodule KollectiveWeb.BookmarkController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/bookmarks
  # Supported params for endless scrolling loaders: ?limit=20&cursor=01J0A...
  def index(conn, params) do
    user = conn.assigns.current_user

    # Fetch preloaded post list maps in exactly one pass
    posts = Posts.list_bookmarked_posts(user, params)
    next_cursor = if posts != [], do: List.last(posts).bookmark_cursor_id, else: nil

    json(conn, %{
      status: "success",
      # Modern Warning-Free Alternative: Serialize directly via your central view contracts
      data:
        Enum.map(posts, fn p ->
          KollectiveWeb.PostJSON.show(%{post: p, likes_count: 0, has_liked: false})
        end),
      next_cursor: to_string(next_cursor)
    })
  end

  # POST /api/v1/posts/:post_id/bookmark
  def toggle(conn, %{"post_id" => post_id}) do
    user = conn.assigns.current_user

    case Posts.toggle_bookmark_post(user, post_id) do
      {:ok, :inserted} ->
        json(conn, %{
          status: "success",
          action: "inserted",
          message: "Post successfully bookmarked."
        })

      {:ok, :removed} ->
        json(conn, %{
          status: "success",
          action: "removed",
          message: "Bookmark successfully removed."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end
end

# lib/kollective_web/controllers/posts/feed_controller.ex
defmodule KollectiveWeb.FeedController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts
  alias KollectiveWeb.PostJSON

  # GET /api/v1/timeline/home
  def home(conn, params) do
    user = conn.assigns.current_user

    # Fetch pre-compiled, hydrated dataset batch
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_home_feed(user, limit: 20, after: params["after"])

    conn
    |> put_status(:ok)
    |> json(%{
      data: PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end

  # Community Feed:
  # GET /api/v1/communities/feed
  # Expected query params from React: ?scope=local&cursor=TIMESTAMP,ID
  def feed(conn, params) do
    current_user = conn.assigns.current_user

    # Directly dispatch params into the unified engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts_for_feed(current_user, params)

    conn
    |> put_status(:ok)
    |> json(%{
      data: PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end
end

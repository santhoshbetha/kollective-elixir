# lib/kollective_web/controllers/hashtag_controller.ex
defmodule KollectiveWeb.HashtagController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/timelines/tag/:tag
  # Accessible optional parameters: ?cursor=01J0A...&limit=20&category=voice
  def show(conn, %{"tag" => tag_name} = params) do
    current_user = conn.assigns.current_user

    # Execute the single-pass index query context block
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_hashtag_timeline(current_user, tag_name, params)

    conn
    |> put_status(:ok)
    # Modern Warning-Free Alternative: Pass straight to your central PostJSON collection
    |> json(%{
      status: "success",
      tag: String.downcase(tag_name),
      data: KollectiveWeb.PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end

  @doc """
  GET /api/discovery/hashtag
  Extracts the hashtag parameter from the raw HTTP URL query string.
  Feeds the frontend endless scrolling discovery grid seamlessly .
  """
  def show_by_query(conn, %{"tag" => tag_name} = params) do
    current_user = conn.assigns.current_user

    # Invoke your optimized, single-pass index query context block
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_hashtag_timeline(current_user, tag_name, params)

    conn
    |> put_status(:ok)
    # Modern Warning-Free Alternative: Serialize directly through your central PostJSON
    |> json(%{
      status: "success",
      tag: String.downcase(String.trim(tag_name)),
      data: KollectiveWeb.PostJSON.index(%{entries: entries}),
      next_cursor: next_cursor
    })
  end

  # Fallback catch-all guard pattern matching malformed empty clicks
  def show_by_query(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      status: "error",
      code: "missing_tag_parameter",
      message: "You must provide a valid 'tag' parameter inside the URL query string parameters."
    })
  end
end

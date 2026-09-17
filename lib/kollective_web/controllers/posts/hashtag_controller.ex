# lib/kollective_web/controllers/posts/hashtag_controller.ex
defmodule KollectiveWeb.HashtagController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts
  alias Kollective.Hashtags.Hashtags
  alias KollectiveWeb.HashtagJSON

  # GET /api/v1/timelines/tag/:tag
  # Accessible optional parameters: ?cursor=01J0A...&limit=20&category=voice
  def show(conn, %{"tag" => tag_name} = params) do
    current_user = conn.assigns.current_user

    # Execute the single-pass index query context block
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_hashtag_timeline(current_user, tag_name, params)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.timeline(tag_name, entries, next_cursor))
  end

  # POST /api/v1/tags/:tag/follow
  def follow(conn, %{"tag" => tag_identifier}) do
    current_user = conn.assigns.current_user
    {:ok, tag_name} = Hashtags.follow_tag(current_user, tag_identifier)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.show(tag_name, true))
  end

  # POST /api/v1/tags/:tag/unfollow
  def unfollow(conn, %{"tag" => tag_identifier}) do
    current_user = conn.assigns.current_user
    {:ok, tag_name} = Hashtags.unfollow_tag(current_user, tag_identifier)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.show(tag_name, false))
  end

  # GET /api/v1/followed_tags
  def followed_tags(conn, _params) do
    current_user = conn.assigns.current_user
    tags = Hashtags.list_followed_tags(current_user)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.list_followed(tags))
  end

  @doc """
  GET /api/discovery/hashtag
  Extracts the hashtag parameter from the raw HTTP URL query string.
  Feeds the frontend endless scrolling discovery grid seamlessly.
  """
  def show_by_query(conn, %{"tag" => tag_name} = params) do
    current_user = conn.assigns.current_user

    # Invoke your optimized, single-pass index query context block
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_hashtag_timeline(current_user, tag_name, params)

    conn
    |> put_status(:ok)
    |> json(HashtagJSON.timeline(tag_name, entries, next_cursor))
  end

  # Fallback catch-all guard pattern matching malformed empty clicks
  def show_by_query(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(HashtagJSON.missing_tag_error())
  end
end

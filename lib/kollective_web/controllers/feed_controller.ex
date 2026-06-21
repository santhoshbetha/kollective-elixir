# lib/kollective_web/controllers/feed_controller.ex
defmodule KollectiveWeb.FeedController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/timeline/home
  def home(conn, params) do
    user = conn.assigns.current_user

    # Fetch pre-compiled, hydrated dataset batch
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_home_feed(user, [limit: 20, after: params["after"]])

    json(conn, %{
      data: serialize_timeline_payload(entries),
      next_cursor: next_cursor
    })
  end

  defp serialize_timeline_payload(entries) do
    Enum.map(entries, fn item ->
      %{
        id: item.post.id,
        content: item.post.content,
        category: item.post.category,
        published_at: item.post.published_at,
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
        },
        organization: if(item.post.organization, do: %{id: item.post.organization.id, name: item.post.organization.name}, else: nil)
      }
    end)
  end

  #Community Feed:
  # lib/kollective_web/controllers/community_controller.ex
  # GET /api/v1/communities/feed
  # Expected query params from React: ?scope=local&cursor=TIMESTAMP,ID
  def feed(conn, params) do
    current_user = conn.assigns.current_user

    # Directly dispatch params into the unified engine
    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts(current_user, params)

    json(conn, %{
      data: serialize_community_posts(entries),
      next_cursor: next_cursor
    })
  end

  defp serialize_community_posts(entries) do
    Enum.map(entries, fn item ->
      %{
        id: item.post.id,
        content: item.post.content,
        category: item.post.category, # Automatically includes both "voice" and regular "posts"
        expires_at: item.post.expires_at,
        inserted_at: item.post.inserted_at,
        likes_count: item.likes_count,
        reblogs_count: item.reblogs_count,
        has_liked: item.has_liked,
        has_reblogged: item.has_reblogged,
        author: %{
          id: item.post.author.id,
          username: item.post.author.username,
          avatar_url: item.post.author.avatar_url
        }
      }
    end)
  end

end

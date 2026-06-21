# lib/kollective_web/controllers/search_controller.ex
defmodule KollectiveWeb.SearchControllerX do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/search
  # Expected query params from React: ?q=elixir&cursor=TIMESTAMP,ID
  def index(conn, params) do
    current_user = conn.assigns[:current_user]

    # 1. Clean, normalize, and extract parameters with fallback defaults
    query_string = String.trim(params["q"] || "")
    cursor = params["cursor"] || params["max_id"] || ""

    cond do
      # Short-circuit immediately to save database memory if the query is blank or too short
      query_string == "" or String.length(query_string) < 3 ->
        json(conn, %{data: [], next_cursor: nil})

      true ->
        # 2. Package and inject pagination options directly into your Unified Search Engine
        search_options = %{"cursor" => cursor}

        # 3. Call the search architecture (Runs FTS vectors + Trigram typo scans + O(1) Batch Hydration)
        %{entries: results, next_cursor: next_cursor} =
          Posts.search_posts(query_string, current_user, search_options)

        # 4. Render the pre-compiled layout structure to your JSON serializer
        json(conn, %{
          data: serialize_search_results(results),
          next_cursor: next_cursor
        })
    end
  end

  # --- Structural Serialization Presentation Helper ---
  defp serialize_search_results(entries) do
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
        liked: item.post.liked,
        reblogged: item.post.reblogged,
        bookmarked: item.post.bookmarked,
        vote_data: item.post.vote_data,
        author: %{
          id: item.post.author.id,
          username: item.post.author.username,
          avatar_url: item.post.author.avatar_url
        }
      }
    end)
  end
end

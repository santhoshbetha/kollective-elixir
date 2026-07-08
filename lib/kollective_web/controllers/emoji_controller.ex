defmodule KollectiveWeb.EmojiController do
  use KollectiveWeb, :controller

  # FIX: Corrected duplicate alias namespace naming error
  alias Kollective.Posts.Posts

  @doc """
  GET /api/v1/custom_emojis
  Exposes all registered platform custom emoticons grouped cleanly by category.
  Feeds the rich text editor composer selection grid seamlessly.
  """
  def index(conn, _params) do
    # Fetch your raw structural data fields via your single-pass query context
    raw_emojis = Posts.list_custom_emojis()

    # OPTIMIZATION: Construct your categorized dictionary cleanly in server memory
    grouped_categories =
      raw_emojis
      |> Enum.group_by(
        fn emoji -> emoji.category || "Custom" end,
        fn emoji ->
          %{
            shortcode: emoji.shortcode,
            url: emoji.url,
            # Gracefully fall back to the primary URL path if static png assets are missing
            static_url: emoji.static_url || emoji.url
          }
        end
      )

    conn
    |> put_status(:ok)
    # Modern Phoenix 1.7 standard: Pass pure maps directly to the json/2 primitive wrapper [1]
    |> json(%{
      status: "success",
      categories: grouped_categories
    })
  end
end

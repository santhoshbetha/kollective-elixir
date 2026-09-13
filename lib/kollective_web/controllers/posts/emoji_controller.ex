# lib/kollective_web/controllers/posts/emoji_controller.ex
defmodule KollectiveWeb.EmojiController do
  use KollectiveWeb, :controller

  alias Kollective.Posts.Posts
  alias KollectiveWeb.EmojiJSON

  @doc """
  GET /api/v1/custom_emojis
  Exposes all registered platform custom emoticons grouped cleanly by category.
  Feeds the rich text editor composer selection grid seamlessly.
  """
  def index(conn, _params) do
    raw_emojis = Posts.list_custom_emojis()

    conn
    |> put_status(:ok)
    |> json(EmojiJSON.grouped(raw_emojis))
  end
end

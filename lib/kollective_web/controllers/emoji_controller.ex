# lib/kollective_web/controllers/emoji_controller.ex
defmodule KollectiveWeb.EmojiController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/custom_emojis
  def index(conn, _params) do
    # Fetch all custom emoji row fields directly out of the database context
    emojis = Posts.list_custom_emojis()
    json(conn, %{data: emojis})
  end
end

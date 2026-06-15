# lib/kollective_web/controllers/admin/emoji_controller.ex
defmodule KollectiveWeb.Admin.EmojiController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  def create(conn, %{"emoji" => emoji_params}) do
    case Posts.create_emoji(emoji_params) do
      {:ok, emoji} ->
        json(conn, %{status: "ok", shortcode: emoji.shortcode})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  #You need to return your custom emojis grouped by category so the picker can
  #organize them (e.g., "Custom", "Logos", "Animations").
  def index(conn, _params) do
    # Group emojis by category in the database
    emojis =
      Kollective.Posts.Posts.list_custom_emojis()
      |> Enum.group_by(& &1.category)

    # Format for the frontend picker
    render(conn, :index, categories: emojis)
  end

end

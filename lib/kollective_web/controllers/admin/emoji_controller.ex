# lib/kollective_web/controllers/admin/emoji_controller.ex
defmodule KollectiveWeb.Admin.EmojiController do
  use KollectiveWeb, :controller
  alias Kollective.Posts.Posts

  # GET /api/v1/admin/custom_emojis/presign
  def presign(conn, %{"shortcode" => shortcode, "content_type" => type}) do
    config = ExAws.Config.new(:s3)
    bucket = "your-r2-bucket"

    # Target path layout for original animated and static assets
    key_gif = "custom_emojis/#{shortcode}.gif"
    key_static = "custom_emojis/#{shortcode}_static.png"

    {:ok, url_gif} = ExAws.S3.presigned_url(config, :put, bucket, key_gif, expires_in: 3600, query_params: [{"Content-Type", type}])
    {:ok, url_static} = ExAws.S3.presigned_url(config, :put, bucket, key_static, expires_in: 3600, query_params: [{"Content-Type", "image/png"}])

    json(conn, %{
      upload_url_gif: url_gif,
      upload_url_static: url_static,
      final_url: "https://your-cdn.com{key_gif}",
      final_static_url: "https://your-cdn.com{key_static}"
    })
  end

  # POST /api/v1/admin/custom_emojis
  def create(conn, %{"emoji" => emoji_params}) do
    case Posts.create_emoji(emoji_params) do
      {:ok, emoji} ->
        conn |> put_status(:created) |> json(%{status: "ok", data: emoji})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def createX(conn, %{"emoji" => emoji_params}) do
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

defmodule KollectiveWeb.Admin.AdminEmojiController do
  use KollectiveWeb, :controller

  alias Kollective.Posts.Posts
  alias KollectiveWeb.ChangesetJSON

  # ─── ACTION 1: GENERATE CUSTOM EMOJI PRESIGNED URLS ───
  # GET /api/v1/admin/custom_emojis/presign?shortcode=kollective_logo&content_type=image/gif
  def presign(conn, %{"shortcode" => shortcode, "content_type" => _content_type}) do
    # Clean the shortcode text input to prevent file directory traversal hacks
    safe_shortcode = String.replace(shortcode, ~r/[^a-zA-Z0-9_\-]/, "")

    # Target path layout for both original animated assets and static frames
    key_gif = "custom_emojis/#{safe_shortcode}.gif"
    key_static = "custom_emojis/#{safe_shortcode}_static.png"

    cdn = Kollective.Storage.cdn_domain()

    # Browser PUTs must go through the same-origin /media proxy. A direct
    # presigned PUT to *.r2.cloudflarestorage.com fails CORS preflight (403),
    # and that endpoint is not a public CDN for <img src>. The proxy writes
    # to R2 server-side via MediaProxyController.upload/2.
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      upload_url_gif: "/media/#{key_gif}",
      upload_url_static: "/media/#{key_static}",
      final_url: "#{cdn}/#{key_gif}",
      final_static_url: "#{cdn}/#{key_static}"
    })
  end

  # ─── ACTION 2: REGISTER COMPLETED EMOJI METADATA ───
  # POST /api/v1/admin/custom_emojis
  # Expected JSON: %{"emoji" => %{"shortcode" => "kollective", "url" => "https://...", "category" => "Logos"}}
  def create(conn, %{"emoji" => emoji_params}) do
    case Posts.create_emoji(emoji_params) do
      {:ok, emoji} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Custom emoji successfully registered onto platform matrices.",
          data: %{id: to_string(emoji.id), shortcode: emoji.shortcode, category: emoji.category}
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # FIX: Call your unified ChangesetJSON function contract directly into json/2
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # ─── ACTION 3: FETCH GROUPED DICTIONARY FOR PICKERS ───
  # GET /api/v1/custom_emojis (Exposed publicly to feed text editor panels)
  def index(conn, _params) do
    # FIX: Corrected namespace module tracking error
    raw_emojis = Posts.list_custom_emojis()

    # Map database collection maps flat into grouped categories natively inside memory
    grouped_emojis =
      raw_emojis
      |> Enum.group_by(fn emoji -> emoji.category || "Custom" end, fn emoji ->
        %{
          shortcode: emoji.shortcode,
          url: emoji.url,
          static_url: emoji.static_url || emoji.url
        }
      end)

    conn
    |> put_status(:ok)
    # FIX: Replaced deprecated render/3 template loops with direct JSON serialization
    |> json(%{
      status: "success",
      categories: grouped_emojis
    })
  end
end

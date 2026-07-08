# Generates the URL that React uses to PUT the encrypted file directly to Cloudflare
# lib/kollective_web/controllers/media_controller.ex
defmodule KollectiveWeb.MediaController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.PostAttachment

  @bucket_name "your-r2-attachments-bucket"
  # Or your custom CDN domain
  @cdn_domain "https://r2.dev"

  # ─── ACTION 1: GENERATE CLOUDFLARE R2 PRESIGNED PUT TICKETS ───
  # GET /api/v1/media/presign
  # Expected params: ?filename=vacation.png&content_type=image/png
  def presign(conn, %{"filename" => filename, "content_type" => content_type}) do
    user = conn.assigns.current_user
    config = ExAws.Config.new(:s3)

    # Secure isolation architecture: attachments/USER_ID/timestamp_filename.ext
    cleaned_ext = Path.extname(filename) |> String.downcase()
    unique_name = "media_#{System.system_time(:second)}#{cleaned_ext}"
    file_key = "attachments/#{user.id}/#{unique_name}"

    # Generate a short-lived 15-minute secure write token to R2 edge pools
    {:ok, upload_url} =
      ExAws.S3.presigned_url(config, :put, @bucket_name, file_key,
        expires_in: 900,
        query_params: [{"Content-Type", content_type}]
      )

    json(conn, %{
      status: "success",
      upload_url: upload_url,
      final_asset_url: "#{@cdn_domain}/#{file_key}"
    })
  end

  # ─── ACTION 2: TRACK AND INSERT FINAL METADATA BINDINGS ───
  # POST /api/v1/media (Replaces Mastodon's legacy multipart upload endpoints)
  # Expected payload: %{"media" => %{"url" => "https://...", "media_type" => "image/jpeg"}}
  def create(conn, %{"media" => media_params}) do
    user = conn.assigns.current_user

    # Safely insert an orphaned post attachment row that will be bound to a Post record shortly after
    attachment_attrs =
      media_params
      # Track ownership for access control
      |> Map.put("user_id", user.id)
      |> Map.put("blurhash", Map.get(media_params, "blurhash", ""))

    case Posts.create_attachment(attachment_attrs) do
      {:ok, attachment} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          data: serialize_attachment_item(attachment)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Failed to create media attachment.",
          errors: KollectiveWeb.ChangesetJSON.error(changeset)
        })
    end
  end

  # ─── ACTION 3: UPDATE ATTACHMENT DESCRIPTION METADATA ───
  # PUT /api/v1/media/:id
  # Expected payload: %{"description" => "A group photo at the park meetup."}
  def update(conn, %{"id" => id, "description" => description}) do
    user = conn.assigns.current_user

    case Repo.get(PostAttachment, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Media attachment not found."})

      attachment ->
        # Enforce security bounds: Only the uploader or post creator can alter metadata description text
        if attachment.user_id != user.id do
          conn |> put_status(:forbidden) |> json(%{error: "unauthorized"})
        else
          case Posts.update_attachment_description(attachment, description) do
            {:ok, updated_attachment} ->
              json(conn, %{status: "success", data: serialize_attachment_item(updated_attachment)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{status: "error", errors: KollectiveWeb.ChangesetJSON.error(changeset)})
          end
        end
    end
  end

  # ─── ACTION 4: FETCH SINGLE ATTACHMENT LOOKUP METRICS ───
  # GET /api/v1/media/:id
  def show(conn, %{"id" => id}) do
    case Repo.get(PostAttachment, id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "Media not found"})
      attachment -> json(conn, %{status: "success", data: serialize_attachment_item(attachment)})
    end
  end

  # --- Private Serialization Mapper ---
  defp serialize_attachment_item(attachment) do
    %{
      id: to_string(attachment.id),
      url: attachment.url,
      type:
        if(String.starts_with?(attachment.media_type || "image", "video"),
          do: "video",
          else: "image"
        ),
      description: Map.get(attachment, :description, ""),
      blurhash: attachment.blurhash
    }
  end
end

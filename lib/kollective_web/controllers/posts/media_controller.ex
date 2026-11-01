# lib/kollective_web/controllers/posts/media_controller.ex
defmodule KollectiveWeb.MediaController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.Posts.PostAttachment
  alias KollectiveWeb.MediaJSON
  alias KollectiveWeb.ChangesetJSON

  @s3_engine Application.compile_env(:kollective, :s3_engine, ExAws.S3)

  # ─── ACTION 1: GENERATE CLOUDFLARE R2 PRESIGNED PUT TICKETS ───
  # GET /api/v1/media/presign
  # Expected params: ?filename=vacation.png&content_type=image/png
  def presign(conn, %{"filename" => filename, "content_type" => content_type}) do
    user = conn.assigns.current_user

    cleaned_ext = Path.extname(filename) |> String.downcase()
    unique_name = "media_#{System.system_time(:second)}_#{System.unique_integer([:positive])}#{cleaned_ext}"
    relative_path = "attachments/#{user.id}/#{unique_name}"
    file_key = Kollective.Storage.object_key(relative_path)

    upload_url =
      cond do
        Mix.env() == :e2e ->
          "/media/#{file_key}"

        @s3_engine != ExAws.S3 ->
          case @s3_engine.presigned_url(s3_config(), :put, Kollective.Storage.bucket_name(), file_key,
                 expires_in: 900,
                 query_params: [{"Content-Type", content_type}]
               ) do
            {:ok, url} -> url
            _ -> "/media/#{file_key}"
          end

        # Browser PUTs must go through the same-origin /media proxy. A direct
        # presigned PUT to *.r2.cloudflarestorage.com fails CORS preflight (403),
        # and that endpoint is not a public CDN for <img src>. The proxy writes
        # to R2 server-side via MediaProxyController.upload/2.
        true ->
          "/media/#{file_key}"
      end

    final_asset_url = "#{Kollective.Storage.cdn_domain()}/#{file_key}"

    conn
    |> put_status(:ok)
    |> json(
      MediaJSON.presign(%{
        upload_url: upload_url,
        final_asset_url: final_asset_url
      })
    )
  end

  defp s3_config do
    if @s3_engine == ExAws.S3 do
      ExAws.Config.new(:s3)
    else
      %{}
    end
  end

  # ─── ACTION 2: TRACK AND INSERT FINAL METADATA BINDINGS ───
  # POST /api/v1/media (Replaces Mastodon's legacy multipart upload endpoints)
  # Expected payload: %{"media" => %{"url" => "https://...", "media_type" => "image/jpeg"}}
  def create(conn, %{"media" => media_params}) do
    user = conn.assigns.current_user

    fx = parse_float(media_params["focal_x"] || get_in(media_params, ["meta", "focus", "x"]) || get_in(media_params, ["focal_point", "x"])) || 0.0
    fy = parse_float(media_params["focal_y"] || get_in(media_params, ["meta", "focus", "y"]) || get_in(media_params, ["focal_point", "y"])) || 0.0

    # Safely insert an orphaned post attachment row that will be bound to a Post record shortly after
    attachment_attrs =
      media_params
      # Track ownership for access control
      |> Map.put("user_id", user.id)
      |> Map.put("blurhash", Map.get(media_params, "blurhash", ""))
      |> Map.put("focal_x", fx)
      |> Map.put("focal_y", fy)

    case Posts.create_attachment(attachment_attrs) do
      {:ok, attachment} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          data: MediaJSON.data(attachment)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Failed to create media attachment.",
          errors: ChangesetJSON.error(changeset)
        })
    end
  end

  # ─── ACTION 3: UPDATE ATTACHMENT DESCRIPTION & FOCAL METADATA ───
  # PUT /api/v1/media/:id
  # Expected payload: %{"description" => "A group photo", "focus" => "0.5,0.5"} or %{"focal_x" => 0.5, "focal_y" => 0.5}
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    case Repo.get(PostAttachment, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Media attachment not found."})

      attachment ->
        # Enforce security bounds: Only the uploader or post creator can alter metadata description text
        if attachment.user_id != user.id do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "unauthorized"})
        else
          attrs = %{}
          attrs = if params["description"], do: Map.put(attrs, :description, params["description"]), else: attrs

          fx = parse_float(params["focal_x"] || get_in(params, ["meta", "focus", "x"]) || get_in(params, ["focal_point", "x"]))
          fy = parse_float(params["focal_y"] || get_in(params, ["meta", "focus", "y"]) || get_in(params, ["focal_point", "y"]))

          attrs = if fx, do: Map.put(attrs, :focal_x, fx), else: attrs
          attrs = if fy, do: Map.put(attrs, :focal_y, fy), else: attrs

          attrs =
            case params["focus"] do
              focus_str when is_binary(focus_str) ->
                case String.split(focus_str, ",") do
                  [x_s, y_s] ->
                    attrs
                    |> Map.put(:focal_x, parse_float(x_s) || 0.0)
                    |> Map.put(:focal_y, parse_float(y_s) || 0.0)
                  _ -> attrs
                end
              %{"x" => x, "y" => y} ->
                attrs
                |> Map.put(:focal_x, parse_float(x) || 0.0)
                |> Map.put(:focal_y, parse_float(y) || 0.0)
              _ -> attrs
            end

          changeset = PostAttachment.changeset(attachment, attrs)
          case Repo.update(changeset) do
            {:ok, updated_attachment} ->
              conn
              |> put_status(:ok)
              |> json(%{status: "success", data: MediaJSON.data(updated_attachment)})

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{status: "error", errors: ChangesetJSON.error(changeset)})
          end
        end
    end
  end

  # ─── ACTION 4: FETCH SINGLE ATTACHMENT LOOKUP METRICS ───
  # GET /api/v1/media/:id
  def show(conn, %{"id" => id}) do
    case Repo.get(PostAttachment, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Media not found"})

      attachment ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: MediaJSON.data(attachment)})
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0
  defp parse_float(val) when is_binary(val) do
    case Float.parse(String.trim(val)) do
      {f, _} -> f
      :error -> nil
    end
  end
  defp parse_float(_), do: nil
end

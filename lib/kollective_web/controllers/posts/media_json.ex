# lib/kollective_web/controllers/posts/media_json.ex
defmodule KollectiveWeb.MediaJSON do
  @moduledoc """
  Unified JSON serializer for Post Media Attachments and S3/R2 direct uploads.
  """

  @doc """
  Formats presigned direct-to-cloud upload URLs for client PUT operations.
  """
  def presign(%{upload_url: upload_url, final_asset_url: final_asset_url}) do
    %{
      status: "success",
      upload_url: upload_url,
      final_asset_url: final_asset_url
    }
  end

  @doc """
  Formats a single media attachment payload.
  """
  def show(%{media: media}), do: show(media)

  def show(media) do
    %{status: "success", data: data(media)}
  end

  @doc """
  Formats a list of media attachments.
  """
  def index(%{media: media_list}), do: index(media_list)

  def index(media_list) when is_list(media_list) do
    Enum.map(media_list, &data/1)
  end

  @doc """
  Serializes a single PostAttachment record or map.
  """
  def data(attachment) do
    media_type = Map.get(attachment, :media_type) || "image"
    fx = Map.get(attachment, :focal_x) || 0.0
    fy = Map.get(attachment, :focal_y) || 0.0

    %{
      id: to_string(attachment.id),
      url: attachment.url,
      type: if(String.starts_with?(media_type, "video"), do: "video", else: "image"),
      description: Map.get(attachment, :description, "") || "",
      blurhash: attachment.blurhash,
      focal_x: fx,
      focal_y: fy,
      meta: %{
        focus: %{
          x: fx,
          y: fy
        }
      }
    }
  end
end

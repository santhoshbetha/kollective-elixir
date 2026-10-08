# For admins to upload emojis, use the Direct-to-S3/R2 pattern. Your Elixir server generates a presigned URL, and the admin's
# browser uploads the file directly to Cloudflare.

defmodule Kollective.Media.Media do
  @doc """
  Generates a presigned URL for general asset uploads.
  Consolidates parameters into a single keyword list options signature.
  """
  def generate_presigned_url(filename, content_type) do
    config = ExAws.Config.new(:s3)
    bucket = Kollective.Storage.bucket_name()
    key = "uploads/#{filename}"

    # FIX: Group all parameters together inside a single, unified options keyword list
    opts = [
      expires_in: 3600,
      # Ensure headers match what your frontend library (Axios, Fetch, Uppy) sends
      query_params: [{"Content-Type", content_type}]
    ]

    case ExAws.S3.presigned_url(config, :put, bucket, key, opts) do
      {:ok, url} -> url
      {:error, reason} -> raise "Failed to generate presigned upload URL: #{inspect(reason)}"
    end
  end

  # Custom Emojis
  # Admin Upload Strategy (R2 Direct)
  # For admins to upload emojis, use the Direct-to-S3/R2 pattern. Your Elixir server generates a
  # presigned URL, and the admin's browser uploads the file directly to Cloudflare
  @doc """
  Generates a presigned URL for direct admin emoji uploads to Cloudflare R2.
  Includes a fallback for parsing file extensions safely.
  """
  def generate_emoji_presign(shortcode, content_type) do
    config = ExAws.Config.new(:s3)
    bucket = Kollective.Storage.bucket_name()

    # Optimization: Infer extensions based on content-type to avoid missing extensions in R2 paths
    extension = extension_from_mime(content_type)
    key = "custom_emojis/#{shortcode}#{extension}"

    opts = [
      expires_in: 3600,
      query_params: [{"Content-Type", content_type}]
    ]

    # FIX: Ensure return values match across both public entry-point functions
    ExAws.S3.presigned_url(config, :put, bucket, key, opts)
  end

  defp extension_from_mime("image/png"), do: ".png"
  defp extension_from_mime("image/jpeg"), do: ".jpg"
  defp extension_from_mime("image/gif"), do: ".gif"
  defp extension_from_mime(_), do: ""
end

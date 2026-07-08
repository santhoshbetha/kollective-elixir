# For admins to upload emojis, use the Direct-to-S3/R2 pattern. Your Elixir server generates a presigned URL, and the admin's
# browser uploads the file directly to Cloudflare.

defmodule Kollective.Media.Media do
  def generate_presigned_url(filename, content_type) do
    config = ExAws.Config.new(:s3)

    {:ok, url} =
      ExAws.S3.presigned_url(
        config,
        :put,
        "your-bucket-name",
        "uploads/#{filename}",
        expires_in: 3600,
        query_params: [{"Content-Type", content_type}]
      )

    url
  end

  # Custom Emojis
  # Admin Upload Strategy (R2 Direct)
  # For admins to upload emojis, use the Direct-to-S3/R2 pattern. Your Elixir server generates a
  # presigned URL, and the admin's browser uploads the file directly to Cloudflare
  def generate_emoji_presign(shortcode, content_type) do
    config = ExAws.Config.new(:s3)
    # Path: /custom_emojis/:shortcode.:ext
    key = "custom_emojis/#{shortcode}"

    ExAws.S3.presigned_url(config, :put, "your-bucket", key,
      expires_in: 3600,
      query_params: [{"Content-Type", content_type}]
    )
  end
end

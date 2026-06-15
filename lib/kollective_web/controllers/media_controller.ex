# Generates the URL that React uses to PUT the encrypted file directly to Cloudflare
defmodule KollectiveWeb.MediaController do
  use KollectiveWeb, :controller
  def presign(conn, %{"filename" => filename, "type" => type}) do
    config = ExAws.Config.new(:s3)
    bucket = "your-r2-bucket"
    key = "attachments/#{filename}"

    # Generate a URL valid for 1 hour
    {:ok, url} = ExAws.S3.presigned_url(config, :put, bucket, key,
      expires_in: 3600,
      query_params: [{"Content-Type", type}]
    )

    #json(conn, %{url: url, file_path: key})
    render(conn, :presign, url: url, file_path: key)
  end

end

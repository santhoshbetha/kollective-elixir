defmodule KollectiveWeb.StorageController do
  use KollectiveWeb, :controller

  @max_chat_file_size 20 * 1024 * 1024

  @doc """
  POST /api/v1/storage/presign
  Generates a cryptographically signed URL constraint tailored for encrypted binaries.
  """
  def presign(conn, %{"file_size" => size}) when size <= @max_chat_file_size do
    file_uuid = Ecto.UUID.generate()

    # 🔒 Privacy Fix: Encrypted files lose their original format identities over the wire.
    # We save everything as a clean, standardized .enc extension block inside our bucket storage keys.
    bucket_object_key = "chats/attachments/#{file_uuid}.enc"

    bucket = System.get_env("R2_BUCKET_NAME") || "kollective-vault"
    config = ExAws.Config.new(:s3)

    opts = [
      expires_in: 900,
      # 🔒 Metadata Protection: Mask content types to hide whether users share images, videos, or PDFs
      query_params: [{"Content-Type", "application/octet-stream"}]
    ]

    case ExAws.S3.presigned_url(config, :put, bucket, bucket_object_key, opts) do
      {:ok, upload_url} ->
        public_file_url = "https://kollective.app/#{bucket_object_key}"

        json(conn, %{
          upload_url: upload_url,
          public_file_url: public_file_url
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to generate security signature", details: inspect(reason)})
    end
  end

  def presign(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "File upload rejected. Must provide valid size under 20MB."})
  end
end

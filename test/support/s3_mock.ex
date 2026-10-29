defmodule KollectiveWeb.S3Mock do
  def presigned_url(_config, :put, bucket_name, file_key, _opts) do
    {:ok, "https://#{bucket_name}/#{file_key}?signed=true"}
  end
end

defmodule KollectiveWeb.Admin.MultiRegionStorageController do
  use KollectiveWeb, :controller
  require Logger

  @doc """
  POST /api/v1/storage/presign
  Generates a cryptographically signed regional bucket upload target URL link.
  Allows secure binary file streaming directly out of the client browser [1].
  """
  def presign(conn, %{"content_type" => content_type, "file_size" => size}) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    # 🌍 DYNAMIC REGIONAL GEOMAPPING MATCHING:
    # Detect which server node is handling the thread and pick the closest bucket context
    local_node_str = Atom.to_string(Node.self())

    user_country = Map.get(user, :country_code) || Map.get(user, :country) || "GLOBAL"

    {bucket_name, region_endpoint} =
      cond do
        String.contains?(local_node_str, "mumbai") or user_country == "IN" ->
          {"kollective-vault-ap-south", "://amazonaws.com"}

        String.contains?(local_node_str, "frankfurt") or user_country in ["EU", "DE", "FR"] ->
          {"kollective-vault-eu-central", "://amazonaws.com"}

        true ->
          # Global fallback storage pool
          {"kollective-vault-us-east", "://amazonaws.com"}
      end

    file_uuid = Ecto.UUID.generate()
    bucket_object_key = "chats/attachments/#{file_uuid}.bin"

    # ExAws Configuration Overrides map to dynamically target the chosen region endpoint
    s3_config =
      ExAws.Config.new(:s3)
      |> Map.put(:host, region_endpoint)
      |> Map.put(:region, bucket_name)

    # 🔑 Cryptographically sign the PUT URL link with a strict 15-minute validity window
    {:ok, upload_url} =
      ExAws.S3.presigned_url(
        s3_config,
        :put,
        bucket_name,
        bucket_object_key,
        expires_in: 900,
        headers: [{"Content-Type", content_type}]
      )

    # Reconstruct the public edge CDN routing link used by remote peers to pull the asset
    public_file_url = "https://kollective.app/#{bucket_object_key}"

    json(conn, %{
      data: %{
        upload_url: upload_url,
        public_file_url: public_file_url,
        allocated_region: bucket_name,
        object_key: bucket_object_key,
        file_size: size
      }
    })
  end
end

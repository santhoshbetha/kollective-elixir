defmodule Kollective.Workers.StorageGarbageCollector do
  use Oban.Worker, queue: :default, max_attempts: 3
  import Ecto.Query
  require Logger

  alias Kollective.Repo

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("🧹 [GARBAGE COLLECTOR]: Initializing cross-regional orphan asset purge pass...")

    # 1️⃣ Identify which regional storage buckets target mapping applies to this local node host
    local_node_str = Atom.to_string(Node.self())

    bucket_name =
      cond do
        String.contains?(local_node_str, "mumbai") -> "kollective-vault-ap-south"
        String.contains?(local_node_str, "frankfurt") -> "kollective-vault-eu-central"
        true -> "kollective-vault-us-east"
      end

    # 2️⃣ Fetch all message file URL references tracked on disk tables to build an allowed tracking index
    # We strip your public edge domain pointers to extract the pure bucket raw object keys
    tracked_keys =
      from(m in "messages",
        where: not is_nil(m.file_url),
        select: m.file_url
      )
      |> Repo.all()
      |> Enum.map(fn url -> String.replace(url, "https://kollective.app", "") end)
      |> MapSet.new()

    # 3️⃣ Query the regional bucket to list all active binary objects currently saved on disk space
    case ExAws.S3.list_objects(bucket_name, prefix: "chats/attachments/") |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} ->
        now_unix = DateTime.utc_now() |> DateTime.to_unix()
        one_day_seconds = 86_400

        Enum.each(objects, fn obj ->
          object_key = obj.key

          last_modified_unix =
            DateTime.from_iso8601(obj.last_modified) |> elem(1) |> DateTime.to_unix()

          # 🚨 PURGE CRITERIA CHECK:
          # If the file key does not exist inside our tracked message database tables index,
          # AND it has sat orphan on storage for more than 24 hours, purge it instantly!
          if not MapSet.member?(tracked_keys, object_key) and
               now_unix - last_modified_unix > one_day_seconds do
            Logger.warning(
              "🗑️ [GARBAGE COLLECTOR]: Purging orphan un-sent file object key: #{object_key} out of bucket #{bucket_name}"
            )

            ExAws.S3.delete_object(bucket_name, object_key) |> ExAws.request!()
          end
        end)

      error ->
        Logger.error(
          "❌ [GARBAGE COLLECTOR FATAL]: Failed to parse Cloudflare R2 bucket indices layers: #{inspect(error)}"
        )
    end

    :ok
  end
end

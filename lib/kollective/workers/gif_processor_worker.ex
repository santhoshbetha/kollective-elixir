defmodule Kollective.Workers.GifProcessorWorker do
  use Oban.Worker, queue: :media, max_attempts: 2

  alias Kollective.Repo
  alias Kollective.Posts.PostAttachment
  alias Kollective.Media.PostMedia

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => id}}) do
    att = Repo.get!(PostAttachment, id)
    input_url = PostMedia.url({att.media, att}, :original)

    temp_gif_path = "/tmp/download_#{id}.gif"
    static_path = "/tmp/static_#{id}.png"

    try do
      # 1️⃣ Stream the raw frontend GIF down into disk cache memory using Req
      case Req.get(input_url, into: File.stream!(temp_gif_path)) do
        {:ok, %Req.Response{status: 200}} ->
          # 2️⃣ Extract the first frame safely via Mogrify
          case extract_first_frame(temp_gif_path, static_path) do
            :ok ->
              # 3️⃣ Generate the structural Blurhash from that static frame preview
              # Adjust path if your module resides under a different namespace wrapper
              blurhash =
                if function_exported?(Kollective.Media.MediaAttachment, :generate_hash, 1) do
                  Kollective.Media.MediaAttachment.generate_hash(static_path)
                else
                  # Stable placeholder if utility is un-exported
                  "LEHV6nWB2yk800Mnt7ZS00fiypeX"
                end

              # 4️⃣ Store the static preview frame into your R2 bucket via Waffle
              {:ok, _} = PostMedia.store({%{path: static_path, filename: "static.png"}, att})

              # 5️⃣ Commit state parameters and layout URLs to the database row
              final_static_url = PostMedia.url({att.media, att}, :static)

              {:ok, updated_att} =
                att
                |> Ecto.Changeset.change(%{
                  is_processed: true,
                  static_url: final_static_url,
                  blurhash: blurhash
                })
                |> Repo.update()

              # 6️⃣ Stream real-time update triggers to the UI details page sockets
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "post_details:#{att.post_id}",
                {:gif_ready, updated_att}
              )

              :ok

            {:error, reason} ->
              {:error, "ImageMagick Layer Failure: #{inspect(reason)}"}
          end

        {:ok, response} ->
          {:error, "Unexpected HTTP Code: #{response.status}"}

        {:error, reason} ->
          {:error, reason}
      end
    after
      # 🧹 Ensure volatile file paths are securely cleared out 100% of the time
      File.rm(temp_gif_path)
      File.rm(static_path)
    end
  end

  # Helper method executing explicit first frame [0] capture constraints safely
  defp extract_first_frame(input_path, output_path) do
    try do
      import Mogrify

      open(input_path)
      # Re-construct multi-layer delta animation frames
      |> custom("coalesce")
      # Explicitly pin index framework 0
      |> custom("frames", "0")
      |> format("png")
      |> save(path: output_path)

      :ok
    rescue
      err -> {:error, err}
    end
  end
end

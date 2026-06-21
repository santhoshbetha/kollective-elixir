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
      case download_file(input_url, temp_gif_path) do
        :ok ->
          gif_args = ["#{temp_gif_path}", "-strip", static_path]

          case System.cmd("convert", gif_args) do
            {_, 0} ->
              {:ok, _} = PostMedia.store({%{path: static_path, filename: "static.png"}, att})

              att
              |> Ecto.Changeset.change(is_processed: true, static_url: PostMedia.url({att.media, att}, :static))
              |> Repo.update!()

              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "post_details:#{att.post_id}",
                {:gif_ready, att}
              )
              :ok

            {error, _} ->
              {:error, "ImageMagick Error: #{inspect(error)}"}
          end

        {:error, reason} ->
          {:error, "Failed to download original GIF: #{inspect(reason)}"}
      end
    # FIX: Use 'after' exclusively to guarantee disk file cleanup
    after
      File.rm(temp_gif_path)
      File.rm(static_path)
    end
  end

  # Quick streaming download utility helper function
  defp download_file(url, local_path) do
    # Using built-in mint or standard HTTP library like Req / Req.get to save memory
    case Req.get(url, into: File.stream!(local_path)) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, response} -> {:error, "HTTP Status #{response.status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end

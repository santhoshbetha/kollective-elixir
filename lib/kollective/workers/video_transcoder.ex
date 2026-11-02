# This worker downloads the original from R2, uses FFmpeg to convert
# it to a optimized .mp4 (H.264/AAC), and replaces the original file.
# lib/kollective/workers/video_transcoder.ex
# added a step to extract the frame before or after the transcoding process.
defmodule Kollective.Workers.VideoTranscoder do
  use Oban.Worker, queue: :media, max_attempts: 3

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Posts.{Post, PostAttachment}
  alias Kollective.Media.PostMedia

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => id}}) do
    att = Repo.get!(PostAttachment, id)
    input_url =
      att.url ||
        (if Map.has_key?(att, :media) and att.media != nil do
           PostMedia.url({att.media, att}, :original)
         else
           nil
         end)

    # Define strict temporary file paths for disk management
    poster_path = "/tmp/poster_#{id}.jpg"
    video_path = "/tmp/transcoded_#{id}.mp4"

    # 1. Instantly alert the database and React UI that processing has commenced
    update_post_processing_status(att.post_id, "processing")

    try do
      # FIX: Adjusted seek window to 1 second to support ultra-short video uploads safely
      poster_args = [
        "-ss",
        "00:00:01",
        "-i",
        input_url,
        "-vframes",
        "1",
        "-q:v",
        "2",
        poster_path,
        "-y"
      ]

      # FIX: Added strict bitrate ceilings to prevent massive mobile data drain spikes
      video_args = [
        "-i",
        input_url,
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-profile:v",
        "high",
        "-level",
        "4.1",
        "-crf",
        "23",
        "-maxrate",
        "2.5M",
        "-bufsize",
        "4M",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-movflags",
        "+faststart",
        "-y",
        video_path
      ]

      with {_, 0} <- System.cmd("ffmpeg", poster_args),
           {:ok, _} <- PostMedia.store({%{path: poster_path, filename: "poster.jpg"}, att}),
           {_, 0} <- System.cmd("ffmpeg", video_args),
           {:ok, _} <- PostMedia.store({%{path: video_path, filename: "video.mp4"}, att}) do
        {:ok, updated_att} =
          att
          |> Ecto.Changeset.change(is_processed: true)
          |> Repo.update()

        update_post_processing_status(att.post_id, "completed")

        # Real-time message push downstream
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "post_details:#{att.post_id}",
          {:video_ready, updated_att}
        )

        :ok
      else
        {:error, reason} ->
          handle_processing_failure(att.post_id, "Upload Failure")
          {:error, "Storage Engine Write Exception: #{inspect(reason)}"}

        {err, _} ->
          handle_processing_failure(att.post_id, "FFmpeg Error")
          {:error, "FFmpeg Transcoding Exception: #{err}"}
      end
    rescue
      e ->
        handle_processing_failure(att.post_id, "Transcoding Error")
        {:error, "Transcoding Exception: #{inspect(e)}"}
    after
      File.rm(poster_path)
      File.rm(video_path)
    end
  end

  # Context Transaction Helpers
  defp update_post_processing_status(post_id, status) do
    from(p in Post, where: p.id == ^post_id)
    |> Repo.update_all(set: [processing_status: status])
  end

  defp handle_processing_failure(post_id, _reason) do
    update_post_processing_status(post_id, "failed")

    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "post_details:#{post_id}",
      :video_failed
    )
  end
end

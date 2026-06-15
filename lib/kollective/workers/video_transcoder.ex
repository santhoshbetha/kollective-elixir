# This worker downloads the original from R2, uses FFmpeg to convert
# it to a optimized .mp4 (H.264/AAC), and replaces the original file.
# lib/kollective/workers/video_transcoder.ex
# added a step to extract the frame before or after the transcoding process.
defmodule Kollective.Workers.VideoTranscoder do
  use Oban.Worker, queue: :media, max_attempts: 3
  alias Kollective.{Repo, Posts.PostAttachment, Media.PostMedia}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => id}}) do
    att = Repo.get!(PostAttachment, id)
    input_url = PostMedia.url({att.media, att}, :original)

    # 1. Extract Poster Image (Fast Seek to 2s)
    poster_path = "/tmp/poster_#{id}.jpg"
    poster_args = ["-ss", "00:00:02", "-i", input_url, "-vframes", "1", "-q:v", "2", poster_path, "-y"]

    with {_, 0} <- System.cmd("ffmpeg", poster_args),
         # 2. Store the poster image in R2 via Waffle
         {:ok, _} <- PostMedia.store({%{path: poster_path, filename: "poster.jpg"}, att}),
         # 3. Transcode Video to Web-Optimized MP4
         video_path <- "/tmp/transcoded_#{id}.mp4",
         video_args <- ["-i", input_url, "-c:v", "libx264", "-crf", "23", "-movflags", "+faststart", "-y", video_path],
         {_, 0} <- System.cmd("ffmpeg", video_args),
         # 4. Store the optimized video
         {:ok, _} <- PostMedia.store({%{path: video_path, filename: "video.mp4"}, att}) do

      # Cleanup and Mark as Processed
      File.rm(poster_path)
      File.rm(video_path)

      att |> Ecto.Changeset.change(is_processed: true) |> Repo.update!()
      :ok
    else
      {err, _} -> {:error, "FFmpeg Error: #{err}"}
      {:error, reason} -> {:error, "Upload Error: #{inspect(reason)}"}
    end
  end
end

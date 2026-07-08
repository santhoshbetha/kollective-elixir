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
  def performX(%Oban.Job{args: %{"attachment_id" => id}}) do
    att = Repo.get!(PostAttachment, id)
    input_url = PostMedia.url({att.media, att}, :original)

    # 1. Extract Poster Image (Fast Seek to 2s)
    poster_path = "/tmp/poster_#{id}.jpg"

    poster_args = [
      "-ss",
      "00:00:02",
      "-i",
      input_url,
      "-vframes",
      "1",
      "-q:v",
      "2",
      poster_path,
      "-y"
    ]

    with {_, 0} <- System.cmd("ffmpeg", poster_args),
         # 2. Store the poster image in R2 via Waffle
         {:ok, _} <- PostMedia.store({%{path: poster_path, filename: "poster.jpg"}, att}),
         # 3. Transcode Video to Web-Optimized MP4
         video_path <- "/tmp/transcoded_#{id}.mp4",
         video_args <- [
           "-i",
           input_url,
           "-c:v",
           "libx264",
           "-crf",
           "23",
           "-movflags",
           "+faststart",
           "-y",
           video_path
         ],
         {_, 0} <- System.cmd("ffmpeg", video_args),
         # 4. Store the optimized video
         {:ok, _} <- PostMedia.store({%{path: video_path, filename: "video.mp4"}, att}) do
      # Cleanup and Mark as Processed
      File.rm(poster_path)
      File.rm(video_path)

      att |> Ecto.Changeset.change(is_processed: true) |> Repo.update!()
      :ok
    else
      {:error, reason} -> {:error, "Upload Error: #{inspect(reason)}"}
      {err, _} -> {:error, "FFmpeg Error: #{err}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => id}}) do
    att = Repo.get!(PostAttachment, id)
    input_url = PostMedia.url({att.media, att}, :original)

    # Define strict temporary file paths for disk management
    poster_path = "/tmp/poster_#{id}.jpg"
    video_path = "/tmp/transcoded_#{id}.mp4"

    # 1. Instantly alert the database and React UI that processing has commenced
    update_post_processing_status(att.post_id, "processing")

    # Wrap in try/ensure block to guarantee local file erasure under failure states
    try do
      poster_args = [
        "-ss",
        "00:00:02",
        "-i",
        input_url,
        "-vframes",
        "1",
        "-q:v",
        "2",
        poster_path,
        "-y"
      ]

      video_args = [
        "-i",
        input_url,
        "-c:v",
        "libx264",
        "-crf",
        "23",
        "-movflags",
        "+faststart",
        "-y",
        video_path
      ]

      with {_, 0} <- System.cmd("ffmpeg", poster_args),
           # 2. Upload extracted first-frame poster to Cloudflare R2 via Waffle
           {:ok, _} <- PostMedia.store({%{path: poster_path, filename: "poster.jpg"}, att}),
           # 3. Process video into clean, web-compressed h264 MP4 stream
           # Safe execution array wrap
           {_, 0} <- System.cmd("ffmpeg", video_args),
           # 4. Upload web-ready asset container payload to R2 bucket
           {:ok, _} <- PostMedia.store({%{path: video_path, filename: "video.mp4"}, att}) do
        # 5. Finalize record states inside database context layer
        {:ok, updated_att} =
          att
          |> Ecto.Changeset.change(is_processed: true)
          |> Repo.update()

        # Update root post container visibility markers
        update_post_processing_status(att.post_id, "completed")

        # 6. CRITICAL REAL-TIME BREAKOUT PUSH
        # Push the finalized asset map to the specific socket stream so the React UI renders live
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
          handle_processing_failure(att.post_id, "FFmpeg Error: #{err}")
          {:error, "FFmpeg Transcoding Exception: #{err}"}
      end
    after
      # This block executes 100% of the time, keeping your server's disk storage clean
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
    #IO.inspect(reason, label: "Video Processing Pipeline Error Intercept")
  end
end

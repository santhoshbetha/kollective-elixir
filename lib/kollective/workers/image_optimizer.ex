defmodule Kollective.Workers.ImageOptimizer do
  use Oban.Worker, queue: :media, max_attempts: 3

  alias Kollective.Repo
  alias Kollective.Posts.PostAttachment
  alias Kollective.Media.PostMedia

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => id}}) do
    # 1️⃣ Pull the structural record context directly from the repository
    att = Repo.get!(PostAttachment, id)
    input_url = PostMedia.url({att.media, att}, :original)

    # Define tight, explicit isolated path boundaries to prevent disk bleed
    optimized_path = "/tmp/optimized_#{id}.jpg"

    try do
      # 2️⃣ Stream down the raw uncompressed frontend file into temporary cache memory
      with {:ok, %{status: 200, body: raw_bytes}} <- Req.get(input_url),
           :ok <- File.write(optimized_path, raw_bytes),

           # 3️⃣ ⚡ RUN GRAPHICS ACCELERATED EXTRACTION COMPRESSION
           # Converts file structure mutably to progressive JPG, shrinks resolution,
           # strips redundant metadata strings, and enforces 82% quality compression.
           {:ok, _out} <- compress_image_file(optimized_path),

           # 4️⃣ Store the clean web-optimized container footprint back into R2 via Waffle
           {:ok, _} <- PostMedia.store({%{path: optimized_path, filename: "optimized.jpg"}, att}) do
        # 5️⃣ Toggle verification status flags inside your database context
        att
        |> Ecto.Changeset.change(is_processed: true, media_type: "image/jpeg")
        |> Repo.update()

        :ok
      else
        error ->
          # Safely bubble up step error parameters directly to the Oban retry matrix logs
          {:error, "Image compression transactional drop: #{inspect(error)}"}
      end
    after
      # 🧹 Disk Cleanup Shield: Erase file system temporary paths immediately
      File.rm(optimized_path)
    end
  end

  #
  # IMAGEMAGICK COMPRESSION WRAPPER ENGINE
  # Enforces strict maximum boundaries on edge width parameters
  #
  defp compress_image_file(path) do
    try do
      import Mogrify

      open(path)
      # Constrain massive resolutions cleanly
      |> resize_to_limit("1600x1200>")
      # Force progressive web rendering properties
      |> custom("interlace", "plane")
      # Strip heavy metadata profiles (EXIF, geolocation data)
      |> custom("strip")
      # High-fidelity balance quality factor threshold
      |> quality(82)
      |> save(in_place: true)

      {:ok, :compressed}
    rescue
      err -> {:error, err}
    end
  end
end

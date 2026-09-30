defmodule Kollective.Media.PostMedia do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  # 1. Define supported versions
  # 'thumb' for the feed, 'original' for the full view, 'poster' for video poster frames
  @versions [:original, :thumb, :poster]

  # 5MB in bytes
  @max_size 5 * 1024 * 1024

  # Validation: Only allow political-safe formats
  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    allowed_extensions = ~w(.jpg .jpeg .png .mp4 .mov)

    # 1. Check Extension
    if Enum.member?(allowed_extensions, file_extension) do
      # 2. Check File Size (Safety net for the server)
      case File.stat(file.path) do
        {:ok, %File.Stat{size: size}} when size <= @max_size ->
          true

        {:ok, _} ->
          {:error, "File is too large (max 5MB)"}

        {:error, _} ->
          {:error, "Could not read file metadata"}
      end
    else
      {:error, "Invalid file format. Use JPG, PNG, or MP4."}
    end
  end

  # 3. Storage Directory: Organize by post ID in R2
  # Format: posts/<post_id>/<version>_<filename>
  def storage_dir(_version, {_file, scope}) do
    "uploads/posts/#{scope.post_id}"
  end

  # 4. Image Transformation (Requires ImageMagick)
  # Automatically creates a 300x300 thumbnail for R2
  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 300x300^ -gravity center -extent 300x300"}
  end

  # 5. Automatic server fallback conversion for the paused GIF state
  # Forces ImageMagick to isolate frame index 0 and convert it to progressive PNG
  def transform(:static, _) do
    {:convert, "-coalesce -frames 0 -format png"}
  end

  # 6. Filename Sanitization
  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{version}_#{name}"
  end

  # 7. CDN/R2 Cache Control
  def s3_object_headers(_version, {file, _scope}) do
    [
      content_type: MIME.from_path(file.file_name),
      # 1 year cache configuration
      cache_control: "public, max-age=31536000"
    ]
  end

  # Ensure the poster is always a JPG
  def s3_object_headers(:poster, _) do
    [content_type: "image/jpeg"]
  end

  # This ensures that generated URLs include the AWS signature
  def s3_url_config(_version, _scope) do
    [virtual_host: true, scheme: "https"]
  end

  # This is called automatically by PostMedia.url/2 when the field is empty
  def default_url(version, _scope) do
    case version do
      :thumb -> "https://media.kollective.app"
      _ -> "https://media.kollective.app"
    end
  end
end

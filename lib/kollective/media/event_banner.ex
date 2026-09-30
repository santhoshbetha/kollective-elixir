defmodule Kollective.Media.EventBanner do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  # 1️⃣ Define supported versions
  # 'thumb' for local calendar grid matrices, 'original' for full event layout views
  @versions [:original, :thumb]

  # Enforce matching 5MB upload constraints across the application context
  @max_size 5 * 1024 * 1024

  # 2️⃣ Validation: Only allow political-safe image format signatures securely
  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    allowed_extensions = ~w(.jpg .jpeg .png)

    if Enum.member?(allowed_extensions, file_extension) do
      # Safety net checking metadata size thresholds on server disk
      case File.stat(file.path) do
        {:ok, %File.Stat{size: size}} when size <= @max_size ->
          true

        {:ok, _} ->
          {:error, "File size exceeds boundary parameters (max 5MB)"}

        {:error, _} ->
          {:error, "Could not extract local file metadata stats"}
      end
    else
      {:error, "Invalid file format. Event banners are bounded to JPG or PNG files."}
    end
  end

  # 3️⃣ Storage Directory: Organizes assets clearly by your specific Event structural ID keys
  # Format destination pattern: events/<event_id>/<version>_<filename>
  def storage_dir(_version, {_file, scope}) do
    "uploads/events/#{scope.id}"
  end

  # 4️⃣ Image Transformation (Requires ImageMagick)
  # Automatically creates a 400x200 crop thumbnail for fast feed lists lookups
  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 400x200^ -gravity center -extent 400x200"}
  end

  # 5️⃣ Filename Sanitization Matrix
  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{version}_#{name}"
  end

  # 6️⃣ CDN/R2 Cache Control and MIME Header Normalization
  def s3_object_headers(_version, {file, _scope}) do
    [
      content_type: MIME.from_path(file.file_name),
      # 1 year static asset caching configuration
      cache_control: "public, max-age=31536000"
    ]
  end

  # This ensures that generated URLs include the proper signature format
  def s3_url_config(_version, _scope) do
    [virtual_host: true, scheme: "https"]
  end

  # This is called automatically by EventBanner.url/2 when the target database column field is empty
  def default_url(version, _scope) do
    case version do
      :thumb -> "https://kollective.app"
      _ -> "https://kollective.app"
    end
  end
end

defmodule Kollective.Media.UserAvatar do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  @versions [:original, :thumb]
  @max_size 5 * 1024 * 1024
  @cdn_host "https://kollective.app"

  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()

    if Enum.member?(~w(.jpg .jpeg .png), file_extension) do
      # FIX: Actually enforce the @max_size rule safely
      case File.stat(file.path) do
        {:ok, %File.Stat{size: size}} when size <= @max_size ->
          true

        {:ok, _} ->
          {:error, "File is too large (max 5MB)"}

        {:error, _} ->
          {:error, "Could not read local file metadata"}
      end
    else
      {:error, "Invalid format type. Use JPG or PNG."}
    end
  end

  # FIX: Prevent crash on initialization when scope.id is nil
  def storage_dir(_version, {_file, %{id: id}}) when not is_nil(id) do
    "uploads/users/#{id}/avatar"
  end

  def storage_dir(_version, _args) do
    "uploads/users/pending/avatar"
  end

  def transform(:thumb, _) do
    # FIX: Changed layout to square geometry constraints (150x150) ideal for human avatar layouts
    {:convert, "-strip -thumbnail 150x150^ -gravity center -extent 150x150"}
  end

  def filename(version, {file, _scope}) do
    # Optimization: Sanitize special characters out of filenames to protect R2 object storage links
    name =
      file.file_name
      |> Path.basename(Path.extname(file.file_name))
      |> String.replace(~r/[^a-zA-Z0-9\-_]/, "_")

    "#{version}_#{name}"
  end

  def s3_object_headers(_version, {file, _scope}) do
    [
      content_type: MIME.from_path(file.file_name),
      cache_control: "public, max-age=31536000"
    ]
  end

  def s3_url_config(_version, _scope), do: [virtual_host: true, scheme: "https"]

  # FIX: Hand off a standard, neutral default placeholder graphic instead of crashing
  def default_url(version, _scope) do
    case version do
      :thumb -> "#{@cdn_host}/images/placeholders/avatar_thumb.png"
      _ -> "#{@cdn_host}/images/placeholders/avatar_original.png"
    end
  end
end

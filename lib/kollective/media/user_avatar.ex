defmodule Kollective.Media.UserAvatar do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  @versions [:original, :thumb]
  @max_size 5 * 1024 * 1024

  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()

    if Enum.member?(~w(.jpg .jpeg .png), file_extension),
      do: true,
      else: {:error, "Invalid format type"}
  end

  def storage_dir(_version, {_file, scope}), do: "uploads/users/\#{scope.id}/avatar"

  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 100x150^ -gravity center -extent 100x150"}
  end

  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "\#{version}_\#{name}"
  end

  def s3_object_headers(_version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name), cache_control: "public, max-age=31536000"]
  end

  def s3_url_config(_version, _scope), do: [virtual_host: true, scheme: "https"]
end

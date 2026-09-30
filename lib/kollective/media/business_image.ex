defmodule Kollective.Media.BusinessImage do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  @versions [:original, :thumb]
  @max_size 5 * 1024 * 1024

  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    allowed_extensions = ~w(.jpg .jpeg .png)

    if Enum.member?(allowed_extensions, file_extension) do
      case File.stat(file.path) do
        {:ok, %File.Stat{size: size}} when size <= @max_size -> true
        _ -> {:error, "Invalid file size parameters"}
      end
    else
      {:error, "Invalid format structure type"}
    end
  end

  # Organize file structures systematically within your Cloudflare folder keys
  def storage_dir(_version, {_file, scope}) do
    "uploads/businesses/#{scope.id}"
  end

  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 150x150^ -gravity center -extent 150x150"}
  end

  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{version}_#{name}"
  end

  def s3_object_headers(_version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name), cache_control: "public, max-age=31536000"]
  end

  def s3_url_config(_version, _scope), do: [virtual_host: true, scheme: "https"]
end

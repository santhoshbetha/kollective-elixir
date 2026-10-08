defmodule Kollective.Media.UserCover do
  use Waffle.Definition
  use Kollective.Media.WaffleEctoDefinition

  @versions [:original]
  @max_size 5 * 1024 * 1024
  @cdn_host "https://kollective.app"

  def validate({file, _scope}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()

    if Enum.member?(~w(.jpg .jpeg .png), file_extension) do
      # FIX: Enforce the defined @max_size constraints on server memory
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

  # FIX: Pattern match carefully to avoid crashing during user registration changesets
  def storage_dir(_version, {_file, %{id: id}}) when not is_nil(id) do
    "uploads/users/#{id}/cover"
  end

  def storage_dir(_version, _args) do
    "uploads/users/pending/cover"
  end

  def filename(version, {file, _scope}) do
    # Optimization: Strip out spaces and special characters for stable object key paths
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

  # FIX: Map a clean fallback cover layout graphic URL string
  def default_url(_version, _scope) do
    "#{@cdn_host}/images/placeholders/user_cover_default.png"
  end
end

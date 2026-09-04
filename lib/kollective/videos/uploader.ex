# lib/kollective/videos/uploader.ex
defmodule Kollective.Videos.Uploader do
  @doc """
  Processes plug multi-part upload binary variables safely.
  Generates a stable, unique cryptographic hash string file path link pointer.
  """
  def upload_video(%Plug.Upload{path: tmp_path, filename: filename}) do
    # 1. Create a unique, collision-proof filename token hash
    unique_id =
      :crypto.hash(:md5, filename <> to_string(System.system_time(:nanosecond)))
      |> Base.encode16(case: :lower)

    extension = Path.extname(filename)
    target_filename = "#{unique_id}#{extension}"

    # 2. Local Disk Storage Fallback Rule: Transfer file stream to private host media block
    # Note: In multi-server staging setups, swap this section with an ExAws.S3 bucket stream dispatch
    dest_path =
      Path.join([
        :code.priv_dir(:kollective),
        "static",
        "uploads",
        "campaign_pitches",
        target_filename
      ])

    # Ensure local directory matrix exists natively on device path hooks
    File.mkdir_p!(Path.dirname(dest_path))

    case File.cp(tmp_path, dest_path) do
      :ok ->
        {:ok, "/uploads/campaign_pitches/#{target_filename}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def upload_video(_), do: {:error, :invalid_binary_payload_parameters}
end

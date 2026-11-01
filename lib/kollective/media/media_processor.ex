defmodule Kollective.Media.MediaProcessor do
  @moduledoc """
  Pipeline processor for uploaded media assets.
  Executes image processing using libvips / Image pipeline, auto-orienting,
  stripping metadata, and constraining bounding resolution to a maximum of 2048px.
  """

  @doc """
  Processes an uploaded file safely through the Image pipeline:
  1. Open image
  2. Auto-orient
  3. Strip/minimize metadata
  4. Thumbnail to max 2048px
  5. Write with quality 85
  """
  def process_upload(upload_path, target_dest) when is_binary(upload_path) and is_binary(target_dest) do
    with {:ok, img} <- Image.open(upload_path),
         {:ok, oriented} <- Image.auto_orient(img),
         {:ok, optimized} <- Image.minimize_metadata(oriented),
         {:ok, thumbnail} <- Image.thumbnail(optimized, 2048),
         :ok <- Image.write(thumbnail, target_dest, quality: 85) do
      {:ok, target_dest}
    else
      error -> error
    end
  end
end

defmodule Kollective.MediaProcessor do
  @moduledoc false
  defdelegate process_upload(upload_path, target_dest), to: Kollective.Media.MediaProcessor
end


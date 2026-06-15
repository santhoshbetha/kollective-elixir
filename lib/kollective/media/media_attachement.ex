defmodule Kollective.Media.MediaAttachment do
  use Kollective.Schemas.Schema

  schema "media_attachments" do
    field :type, Kollective.Media.PostMedia.Type
    field :url, :string      # Full URL to S3
    field :blurhash, :string # For blurred placeholders (Mastodon standard)

    # URL for the extracted first frame
    field :static_url, :string

    belongs_to :author, Kollective.Accounts.User, foreign_key: :author_id
    belongs_to :post, Kollective.Posts.Post, foreign_key: :post_id

    timestamps()
  end

  # Generate the Hash (Elixir)
  # The Blurhash algorithm requires raw RGB pixel data. If you are using Cloudflare R2, you should
  # generate the hash right after the user notifies the server that the upload is complete
  def generate_hash(image_path) do
    # 1. Downscale the image (recommended for speed)
    # Encoding a massive image is slow; 32px is plenty for a blur
    import Mogrify
    {:ok, pixels} =
      open(image_path)

      |> custom("resize", "32x32!")
      |> format("rgb")
      |> save()

      |> File.read!()
      |> :binary.bin_to_list()

    # 2. Encode to Blurhash string (4x3 components is standard)
    BlurHash.encode(pixels, 32, 32, 4, 3)
  end
end

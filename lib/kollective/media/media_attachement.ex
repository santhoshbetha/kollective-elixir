defmodule Kollective.Media.MediaAttachment do
  use Kollective.Schemas.Schema
  # 💡 1. Add this macro helper to enable Waffle-Ecto casting
  use Waffle.Ecto.Schema
  import Mogrify

  schema "media_attachments" do
    field :file, Kollective.Media.PostMedia.Type
    field :type, :string
    # Full URL to S3
    field :url, :string
    field :description, :string
    # For blurred placeholders (Mastodon standard)
    field :blurhash, :string

    # URL for the extracted first frame
    field :static_url, :string
    field :focal_x, :float, default: 0.0
    field :focal_y, :float, default: 0.0

    belongs_to :author, Kollective.Accounts.User, foreign_key: :author_id
    belongs_to :post, Kollective.Posts.Post, foreign_key: :post_id

    timestamps()
  end

  @doc """
  Changeset helper for attachments.
  Waffle.Ecto provides `cast_attachments/3` to process file uploads automatically.
  """
  def changeset(media_attachment, attrs) do
    media_attachment
    # Cast standard metadata parameters
    |> Ecto.Changeset.cast(attrs, [
      :type,
      :description,
      :url,
      :blurhash,
      :static_url,
      :focal_x,
      :focal_y,
      :author_id,
      :post_id
    ])
    # Cast and trigger the uploader file stream logic automatically
    |> cast_attachments(attrs, [:file])
    |> Ecto.Changeset.validate_required([:file, :type])
  end

  # Generate the Hash (Elixir)
  # The Blurhash algorithm requires raw RGB pixel data. If you are using Cloudflare R2, you should
  # generate the hash right after the user notifies the server that the upload is complete
  def generate_hashX(image_path) do
    # 1. Downscale the image (recommended for speed)
    # Encoding a massive image is slow; 32px is plenty for a blur
    import Mogrify

    # 🔄 FIX 1: Bind the saved Mogrify struct to a variable
    processed_image =
      open(image_path)
      |> custom("resize", "32x32!")
      |> format("rgb")
      # 💡 Use in_place: true to avoid creating orphan temp files
      |> save(in_place: true)

    # 🔄 FIX 2: Extract the string path (.path) out of the struct before reading bytes
    # 🔄 FIX: Remove the tuple wrapper. bin_to_list/1 returns a plain [byte()] list directly.
    pixels =
      processed_image.path
      |> File.read!()
      |> :binary.bin_to_list()

    # 2. Encode to Blurhash string (4x3 components is standard)
    BlurHash.encode(pixels, 32, 32, 4, 3)
  end

  # ImageMagick Direct Format Crash (Bug) (in previous version above fixed below)
  # When executing |> format("rgb"), ImageMagick changes the output extension signature.
  # If the original image was named photo.jpg, rewriting the bytes flatly to "rgb" via in_place: true
  # changes the file's binary stream structure but keeps the original path name,
  # occasionally failing to append the raw binary signature.

  @doc """
  Generates a Blurhash string from an image path.
  Expects a string path pointing to a local temporary image file.
  """
  def generate_hash(image_path) do
    # Generate a unique path for the raw RGB pixel data payload
    temp_rgb_path = "#{image_path}_32x32.rgb"

    try do
      # 1. Downscale the image and dump the raw RGB pixels to our temp path
      open(image_path)
      |> custom("resize", "32x32!")
      |> format("rgb")
      # FIX: Returns the correct saved struct output reference
      |> save(path: temp_rgb_path)

      # 2. Extract the raw bytes array
      pixels =
        temp_rgb_path
        |> File.read!()
        |> :binary.bin_to_list()

      # 3. Encode to Blurhash string using 4x3 components (Mastodon/Wolt standard layout)
      # Input dimensions match our resized 32x32 layout bounds exactly
      BlurHash.encode(pixels, 32, 32, 4, 3)
    after
      # Cleanup the temporary RGB stream file safely to avoid leaking server storage space
      File.rm(temp_rgb_path)
    end
  end
end

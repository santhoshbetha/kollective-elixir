# lib/kollective/posts/post_attachment.ex
defmodule Kollective.Posts.PostAttachment do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "post_attachments" do
    # Track the final direct asset path string cleanly
    field :url, :string
    field :media_type, :string
    field :description, :string
    field :blurhash, :string, default: ""
    field :focal_x, :float, default: 0.0
    field :focal_y, :float, default: 0.0

    belongs_to :post, Kollective.Posts.Post
    # Track ownership to lock metadata updates securely to the uploader
    belongs_to :user, Kollective.Accounts.User

    timestamps()
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:url, :media_type, :description, :blurhash, :focal_x, :focal_y, :post_id, :user_id])
    |> validate_required([:url, :media_type, :user_id])
  end
end

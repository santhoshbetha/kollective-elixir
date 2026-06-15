defmodule Kollective.Posts.PostAttachment do
  use Kollective.Schemas.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "post_attachments" do
    field :media, Kollective.Media.PostMedia.Type
    field :alt_text, :string
    field :content_type, :string # Store the detected type
    belongs_to :post, Kollective.Posts.Post
    field :is_processed, :boolean, default: false

    timestamps()
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:content_type, :alt_text])
    |> cast_attachments(attrs, [:media])
    |> validate_required([:media])
  end
end

#create index(:post_attachments, [:post_id])

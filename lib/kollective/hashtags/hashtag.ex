defmodule Kollective.Hashtags.Hashtag do
  use Kollective.Schemas.Schema
  import Ecto.Changeset
  # import Ecto.Changeset

  # alias Ecto.Multi
  # alias Kollective.Hashtags.Hashtag
  # alias Kollective.Repo

  # TODO check later : linking to Post instead of Object, since hashtags are more post-centric in our design. We can always add a separate join table for objects if needed.

  schema "hashtags" do
    # Caches downcase lowercase string keys (e.g. "grassroots")
    field :name, :string

    many_to_many :posts, Kollective.Posts.Post, join_through: "posts_hashtags"

    timestamps()
  end

  def changeset(hashtag, attrs) do
    hashtag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> unique_constraint(:name)
  end
end

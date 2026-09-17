defmodule Kollective.Hashtags.TagFollow do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "tag_follows" do
    field :tag_name, :string
    belongs_to :user, Kollective.Accounts.User

    timestamps()
  end

  def changeset(tag_follow, attrs) do
    tag_follow
    |> cast(attrs, [:user_id, :tag_name])
    |> validate_required([:user_id, :tag_name])
    |> unique_constraint([:user_id, :tag_name])
  end
end

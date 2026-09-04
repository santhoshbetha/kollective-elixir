defmodule Kollective.Posts.Like do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "likes" do
    belongs_to :user, Kollective.Accounts.User, type: Ecto.ULID
    belongs_to :post, Kollective.Posts.Post, type: Ecto.ULID
    timestamps()
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
    |> unique_constraint([:user_id, :post_id])
  end
end

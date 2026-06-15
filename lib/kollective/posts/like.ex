defmodule Kollective.Posts.Like do
  use Ecto.Schema
  import Ecto.Changeset

  schema "likes" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post
    timestamps()
  end

  def changeset(like, attrs) do
    like

    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
    |> unique_constraint([:user_id, :post_id])
  end
end

# This is the join table that connects a User to a Post.
# We use a unique_constraint to ensure a user can only repost a specific post once.
defmodule Kollective.Posts.Repost do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "reposts" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post

    timestamps()
  end

  def changeset(repost, attrs) do
    repost
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
    # Prevents duplicate rows in Postgres
    |> unique_constraint([:user_id, :post_id])
  end
end

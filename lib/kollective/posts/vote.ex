defmodule Kollective.Posts.Vote do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "votes" do
    field :type, Ecto.Enum, values: [:up, :down]
    belongs_to :user, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post

    timestamps(type: :utc_datetime)
  end
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:type, :user_id, :post_id])
    |> validate_required([:type, :user_id, :post_id])
    # Ensures the app respects the DB unique constraint
    |> unique_constraint([:user_id, :post_id])
  end
end

defmodule Kollective.Favourites.Favourite do
  use Kollective.Schemas.Schema

  import Ecto.Changeset

  schema "favourites" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post, foreign_key: :post_id

    timestamps()
  end

  @doc false
  def changeset(favourite, attrs) do
    favourite
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
    # Handles the database unique constraint gracefully
    |> unique_constraint([:user_id, :post_id], name: :favourites_user_id_post_id_index)
  end
end

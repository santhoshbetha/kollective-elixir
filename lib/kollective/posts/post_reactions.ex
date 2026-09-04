defmodule Kollective.Posts.PostReaction do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "post_reactions" do
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    belongs_to :post, Kollective.Posts.Post, foreign_key: :post_id

    # Store the literal emoji character string (e.g., "🔥", "👍")
    field :emoji, :string

    timestamps()
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:user_id, :post_id, :emoji])
    |> validate_required([:user_id, :post_id, :emoji])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:post_id)
    |> unique_constraint([:user_id, :post_id, :emoji],
      name: :post_reactions_composite_unique_index
    )
  end
end

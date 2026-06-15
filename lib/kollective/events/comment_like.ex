defmodule Kollective.Events.CommentLike do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "comment_likes" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :comment, Kollective.Events.Comment

    timestamps()
  end

  def changeset(comment_like, attrs) do
    comment_like
    |> cast(attrs, [:user_id, :comment_id])
    |> validate_required([:user_id, :comment_id])
    # Connects the unique index from the migration to the changeset
    |> unique_constraint([:user_id, :comment_id], name: :comment_likes_user_id_comment_id_index)
  end
end

# lib/kollective/posts/post_bookmark.ex
defmodule Kollective.Posts.PostBookmark do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "post_bookmarks" do
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    belongs_to :post, Kollective.Posts.Post, foreign_key: :post_id

    timestamps()
  end

  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:post_id)
    |> unique_constraint([:user_id, :post_id], name: :bookmarks_user_id_post_id_index)
  end
end

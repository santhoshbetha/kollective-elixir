# lib/kollective/posts/thread_mute.ex
defmodule Kollective.Posts.ThreadMute do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "thread_mutes" do
    belongs_to :user, Kollective.Accounts.User
    # We point to the post that started the thread
    belongs_to :root_post, Kollective.Posts.Post

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:user_id, :root_post_id])
    |> validate_required([:user_id, :root_post_id])
    |> unique_constraint([:user_id, :root_post_id])
  end
end

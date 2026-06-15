defmodule Kollective.Videos.Like do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "video_likes" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :video, Kollective.Videos.CandidateVideo
    timestamps()
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :video_id])
    |> validate_required([:user_id, :video_id])
    |> unique_constraint([:user_id, :video_id])
  end
end

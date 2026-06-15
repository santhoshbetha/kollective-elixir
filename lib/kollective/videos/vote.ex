defmodule Kollective.Videos.Vote do
  use Kollective.Schemas.Schema

  schema "votes" do
    # type: 1 for upvote, -1 for downvote, 0 for neutral/like
    field :type, :integer
    belongs_to :user, Kollective.Accounts.User
    belongs_to :video, Kollective.Videos.CandidateVideo

    timestamps()
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:type, :user_id, :video_id])
    |> validate_inclusion(:type, [-1, 1])
    |> unique_constraint([:user_id, :video_id], name: :video_votes_user_id_video_id_index)
  end
end

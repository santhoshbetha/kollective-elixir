defmodule Kollective.Polls.PollVote do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "poll_votes" do
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id, references: :id
    belongs_to :poll, Kollective.Polls.Poll, foreign_key: :poll_id, references: :id
    belongs_to :option, Kollective.Polls.PollOption, foreign_key: :option_id, references: :id

    timestamps()
  end

  def changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:user_id, :poll_id, :option_id])
    |> validate_required([:user_id, :poll_id, :option_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:option_id)
    |> unique_constraint([:user_id, :poll_id], name: :poll_votes_user_id_poll_id_index)
  end
end

#  create unique_index(:poll_votes, [:user_id, :poll_id, :option_id])

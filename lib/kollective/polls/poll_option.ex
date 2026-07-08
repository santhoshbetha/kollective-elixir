defmodule Kollective.Polls.PollOption do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "poll_options" do
    field :title, :string
    field :votes_count, :integer, default: 0

    belongs_to :poll, Kollective.Polls.Poll
    has_many :votes, Kollective.Polls.PollVote, foreign_key: :option_id

    timestamps()
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end

# Constituent-Only Q&A adds a powerful accountability layer. It ensures that candidates
# (from State House to Congress) are answering people they actually represent, preventing
# "out-of-district" spam from drowning out local voices.

# 1. The Question Schema (lib/kollective/videos/question.ex)
# This schema tracks the question, the asker, and the target candidate.

defmodule Kollective.Videos.Question do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "questions" do
    field :content, :string
    field :is_answered, :boolean, default: false

    # The Asker
    belongs_to :user, Kollective.Accounts.User
    # The Candidate
    belongs_to :candidate, Kollective.Accounts.User
    # The Video Reply
    has_one :answer_video, Kollective.Videos.CandidateVideo

    timestamps()
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:content, :candidate_id, :user_id])
    |> validate_required([:content, :candidate_id, :user_id])
    |> validate_length(:content, max: 280)
  end
end

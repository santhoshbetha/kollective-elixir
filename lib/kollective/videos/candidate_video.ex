defmodule Kollective.Videos.CandidateVideo do
  use Kollective.Schemas.Schema

  schema "candidate_videos" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :question, Kollective.Videos.Question
    field :video_url, :string
    # Added for preview images
    field :thumbnail_url, :string
    field :title, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:published, :pending, :rejected], default: :published

    # Target Scope: :state_rep, :state_senate, :congress, :governor, :president
    field :scope, Ecto.Enum, values: [:state_rep, :state_senate, :congress, :governor, :president]

    # The specific ID/Name of the district (if applicable)
    field :target_district, :string
    field :target_state, :string
    field :target_country, :string, default: "US"

    # Engagement Counters (Counter Caches)
    field :upvotes_count, :integer, default: 0
    field :downvotes_count, :integer, default: 0
    field :likes_count, :integer, default: 0

    has_many :votes, Kollective.Videos.Vote, foreign_key: :video_id
    has_many :likes, Kollective.Videos.Like, foreign_key: :video_id

    timestamps()
  end
end

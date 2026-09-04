# priv/repo/migrations/XXXXXXXXXXXXXX_create_candidate_videos.exs
defmodule Kollective.Repo.Migrations.CreateCandidateVideos do
  use Ecto.Migration

  def change do
    create table(:candidate_videos) do
      # 🗳️ Candidate pitch content metadata fields
      add :title, :string, null: false, default: "Campaign Manifesto Pitch"
      add :video_url, :string, null: false
      add :votes_count, :integer, null: false, default: 0

      # 🗺️ Target scope parameters tracking which election tier this video represents
      # "congress", "state_senate", "state_rep"
      add :office_level, :string, null: false
      # e.g., "TX-10", "SD-24"
      add :district_code, :string, null: false

      # 👤 Reference index linking straight to your existing User schema ID
      add :user_id, :binary_id, null: false

      timestamps()
    end

    # 🚀 Performance Indices: Accelerate regional candidate score rankings
    create index(:candidate_videos, [:office_level, :district_code])
    create index(:candidate_videos, [:votes_count])
    create index(:candidate_videos, [:user_id])
  end
end

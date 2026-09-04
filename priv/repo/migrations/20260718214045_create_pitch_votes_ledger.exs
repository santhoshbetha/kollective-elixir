# priv/repo/migrations/20260715181400_create_pitch_votes_ledger.exs
defmodule Kollective.Repo.Migrations.CreatePitchVotesLedger do
  use Ecto.Migration

  def change do
    create table(:pitch_votes) do
      # References index links pointing to users and video pitch identifiers
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :candidate_video_id, references(:candidate_videos, on_delete: :delete_all), null: false

      timestamps()
    end

    # 🎯 THE SECURITY CONSTRAINT: Enforcing a composite unique index completely
    # blocks a single user from inserting duplicate votes for the same video pitch.
    create unique_index(:pitch_votes, [:user_id, :candidate_video_id])
    create index(:pitch_votes, [:candidate_video_id])
  end
end

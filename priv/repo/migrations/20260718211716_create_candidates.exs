# priv/repo/migrations/XXXXXXXXXXXXXX_create_candidates.exs
defmodule Kollective.Repo.Migrations.CreateCandidates do
  use Ecto.Migration

  def change do
    create table(:candidates) do
      add :profession, :string, null: false
      add :manifesto, :text, null: false
      add :video_url, :string, null: false
      add :votes_count, :integer, null: false, default: 0
      add :country, :string, null: false, default: "US"
      add :district_id, :string, null: false
      # Casts straight to your existing users index
      add :account_id, :binary_id, null: false

      timestamps()
    end

    # 🚀 Performance Optimization: Accelerate regional lookup rankings by score
    create index(:candidates, [:country, :district_id])
    create index(:candidates, [:votes_count])
  end
end

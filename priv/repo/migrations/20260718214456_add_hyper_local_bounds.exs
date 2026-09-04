# priv/repo/migrations/20260716150000_add_hyper_local_bounds.exs
defmodule Kollective.Repo.Migrations.AddHyperLocalBounds do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # e.g., "Tehsil/Taluka Name" or "Assembly Segment"
      add :sub_district, :string, null: true
      # Hyper-local ward or neighborhood block key
      add :polling_booth_id, :string, null: true

      add :street_address, :string, null: true
      add :county, :string, null: true
      add :school_district_code, :string, null: true
      add :city_council_district_code, :string, null: true
    end

    alter table(:candidate_videos) do
      add :sub_district, :string, null: true
      add :polling_booth_id, :string, null: true
    end

    # Create composite indices to optimize database lookups at scale
    create index(:candidate_videos, [:polling_booth_id])
    create index(:candidate_videos, [:sub_district])
  end
end

defmodule Kollective.Repo.Migrations.CreatePoliticalDistricts do
  use Ecto.Migration

  def change do
    create table(:political_districts, primary_key: false) do
      # Enforces system-wide ULID structural layouts
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :level, :integer, null: false
      add :type_label, :string, null: false
      add :state, :string
      add :country, :string, null: false, default: "US"

      # ─── THE SELF JOIN ───
      # Self-references the same table using the ULID :binary_id type
      add :parent_id, references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    # ─── PERFORMANCE INDICES ───
    # Optimizes traversal of the hierarchical tree structure
    create index(:political_districts, [:parent_id])

    # Speeds up region filtering scans (e.g. Find all districts in TX)
    create index(:political_districts, [:country, :state, :level])
  end
end

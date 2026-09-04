defmodule Kollective.Repo.Migrations.CreateCities do
  use Ecto.Migration

  def change do
    create table(:cities, primary_key: false) do
      # Enforces unified Ecto.ULID binary format globally
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :state, :string, null: false
      add :country, :string, null: false
      add :external_id, :string, null: false

      add :latitude, :float
      add :longitude, :float

      timestamps()
    end

    # ⚡ PERFORMANCE WINNERS
    # Enforces absolute uniqueness for external data syncing (Google/Geoapify)
    create unique_index(:cities, [:external_id])

    # Speeds up local geographic lookup queries (e.g., search within a state/country)
    create index(:cities, [:country, :state])
  end
end

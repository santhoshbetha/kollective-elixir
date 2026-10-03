defmodule Kollective.Repo.Migrations.CreateFeatureFlags do
  use Ecto.Migration

  def change do
    create table(:feature_flags, primary_key: false) do
      # We use the unique key string as the primary key for ultra-fast indexing
      add :key, :string, primary_key: true
      add :enabled, :boolean, default: false, null: false
      add :description, :string
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    # Explicit index to guarantee quick lookups during boot hydration sequences
    create unique_index(:feature_flags, [:key])
  end
end

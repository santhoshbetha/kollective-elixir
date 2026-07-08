defmodule Kollective.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      # Configured for system-wide ULID support
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      # Required by your filter index
      add :event_status, :string, default: "published", null: false

      # Your 3 distinct geographical district level tiers
      add :origin_district_l1, :string
      add :origin_district_l2, :string
      add :origin_district_l3, :string

      # Geospatial coordinates required by your AddCubeEarthDistanceIndices migration
      add :latitude, :float
      add :longitude, :float

      # Association linking back to the user who created the event
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:events, [:user_id])
  end
end

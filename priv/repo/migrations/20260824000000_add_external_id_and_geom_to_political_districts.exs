defmodule Kollective.Repo.Migrations.AddExternalIdAndGeomToPoliticalDistricts do
  use Ecto.Migration

  def change do
    alter table(:political_districts) do
      add_if_not_exists :external_id, :string
      add_if_not_exists :geom, :geometry
    end

    create_if_not_exists index(:political_districts, [:external_id])
    create_if_not_exists index(:political_districts, [:geom], using: :gist)
  end
end

defmodule Kollective.Repo.Migrations.ActivatePostgis do
  use Ecto.Migration

  def up do
    # Activates the PostGIS geospatial engine
    execute "CREATE EXTENSION IF NOT EXISTS postgis;"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS postgis;"
  end
end

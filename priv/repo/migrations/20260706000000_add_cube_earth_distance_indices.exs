defmodule Kollective.Repo.Migrations.AddCubeEarthDistanceIndices do
  use Ecto.Migration

  def change do
    # 1. Enable standard geometric calculations extensions
    execute "CREATE EXTENSION IF NOT EXISTS cube;"
    execute "CREATE EXTENSION IF NOT EXISTS earthdistance;"

    # 2. Add structural expression GIST index targeting point locations
    execute """
    CREATE INDEX IF NOT EXISTS events_spatial_ll_idx
    ON events USING GIST (ll_to_earth(latitude, longitude));
    """
  end
end

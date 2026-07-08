defmodule Kollective.Repo.Migrations.UpgradeObanSchemaToV11 do
  use Ecto.Migration

  def up do
    # Smoothly steps through every required upgrade layer up to v11
    Oban.Migration.up(version: 11)
  end

  def down do
    # Gracefully rolls the schemas back down to your previous version if needed
    Oban.Migration.down(version: 1)
  end
end

defmodule Kollective.Repo.Migrations.AddBadgeTypeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists :badge_type, :string, default: "ClassicBlue"
    end
  end
end

defmodule Kollective.Repo.Migrations.AddUnderInvestigationToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists :under_investigation, :boolean, default: false, null: false
    end
  end
end

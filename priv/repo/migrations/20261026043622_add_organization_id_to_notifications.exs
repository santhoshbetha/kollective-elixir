defmodule Kollective.Repo.Migrations.AddOrganizationIdToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :organization_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
    end

    create index(:notifications, [:organization_id, :inserted_at])
  end
end

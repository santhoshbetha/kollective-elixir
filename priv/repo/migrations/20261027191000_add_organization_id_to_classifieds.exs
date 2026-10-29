defmodule Kollective.Repo.Migrations.AddOrganizationIdToClassifieds do
  use Ecto.Migration

  def change do
    alter table(:classifieds) do
      add :organization_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: true
    end

    create index(:classifieds, [:organization_id])
  end
end

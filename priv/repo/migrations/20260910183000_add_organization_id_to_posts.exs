defmodule Kollective.Repo.Migrations.AddOrganizationIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :organization_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: true
    end

    create index(:posts, [:organization_id])
  end
end

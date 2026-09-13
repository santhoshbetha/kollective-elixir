defmodule Kollective.Repo.Migrations.CreateOrganizationMemberships do
  use Ecto.Migration

  def change do
    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, default: "contributor", null: false
      add :status, :string, default: "pending", null: false

      timestamps()
    end

    create unique_index(:organization_memberships, [:user_id, :organization_id],
             name: :org_memberships_user_org_index
           )

    create index(:organization_memberships, [:organization_id])
    create index(:organization_memberships, [:user_id])
  end
end

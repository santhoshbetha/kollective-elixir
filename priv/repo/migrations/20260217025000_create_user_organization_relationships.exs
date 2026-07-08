defmodule Kollective.Repo.Migrations.CreateUserOrganizationRelationships do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:user_organization_relationships) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      # e.g., member, admin, follower
      add :relationship_type, :string, default: "member", null: false

      timestamps()
    end

    create_if_not_exists index(:user_organization_relationships, [:user_id])
    create_if_not_exists index(:user_organization_relationships, [:organization_id])
    create_if_not_exists index(:user_organization_relationships, [:user_id, :organization_id])
  end
end

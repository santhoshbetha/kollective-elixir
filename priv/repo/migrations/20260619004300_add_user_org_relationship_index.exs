defmodule Kollective.Repo.Migrations.AddUserOrgRelationshipIndex do
  use Ecto.Migration

  def change do
    # Creates a high-speed targeted search index path for followed organizations
    create index(:user_organization_relationships, [:user_id, :organization_id])
  end
end

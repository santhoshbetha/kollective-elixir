defmodule YourApp.Repo.Migrations.CreateUserRelationships do
  use Ecto.Migration

  def change do
    create table(:user_relationships) do
      add :source_id, references(:users, on_delete: :delete_all), null: false
      add :target_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false, default: "follow"

      timestamps()
    end

    # Optimize query lookups and enforce unique relationships
    create index(:user_relationships, [:source_id, :type])
    create unique_index(:user_relationships, [:source_id, :target_id, :type])
  end
end

defmodule Kollective.Repo.Migrations.CreateTagFollows do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:tag_follows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_name, :string, null: false

      timestamps()
    end

    create_if_not_exists unique_index(:tag_follows, [:user_id, :tag_name])
    create_if_not_exists index(:tag_follows, [:user_id])
  end
end

defmodule Kollective.Repo.Migrations.CreateLikes do
  use Ecto.Migration

  def change do
    create table(:likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    # Enforce uniqueness at the database level
    create unique_index(:likes, [:user_id, :post_id])
  end
end

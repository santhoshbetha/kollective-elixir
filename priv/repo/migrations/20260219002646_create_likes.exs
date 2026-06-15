defmodule Kollective.Repo.Migrations.CreateLikes do
  use Ecto.Migration

  def change do
    create table(:likes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      timestamps()
    end

    # Enforce uniqueness at the database level
    create unique_index(:likes, [:user_id, :post_id])
  end
end

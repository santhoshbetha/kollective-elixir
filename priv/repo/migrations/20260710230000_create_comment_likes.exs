defmodule Kollective.Repo.Migrations.CreateCommentLikes do
  use Ecto.Migration

  def change do
    create table(:comment_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :comment_id, references(:event_comments, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:comment_likes, [:user_id, :comment_id])
  end
end

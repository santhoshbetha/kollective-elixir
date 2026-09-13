defmodule Kollective.Repo.Migrations.AlterPostsUserIdFk do
  use Ecto.Migration

  def change do
    # Drop old constraint and allow user_id to be nullable ONLY when an account is deleted entirely
    drop constraint(:posts, "posts_user_id_fkey")

    alter table(:posts) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: true
    end
  end
end

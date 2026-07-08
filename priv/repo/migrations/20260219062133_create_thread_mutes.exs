# Thread Muting (also known as Conversation Muting in Mastodon), you allow a user to silence all
# future notifications from a specific viral thread. Since you already have a root_post_id, this is very efficient

defmodule Kollective.Repo.Migrations.CreateThreadMutes do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:thread_mutes) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # References the ID of the very first post in the thread
      add :root_post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create_if_not_exists unique_index(:thread_mutes, [:user_id, :root_post_id])
  end
end

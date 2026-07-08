defmodule Kollective.Repo.Migrations.CreateHomeFeedEntries do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:home_feed_entries) do
      # The timeline owner
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # The distributed post
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    # Composite unique index ensures no duplicate posts slip into a timeline
    create_if_not_exists unique_index(:home_feed_entries, [:user_id, :post_id])
    # Indexed for chronological cursor pagination sorting queries
    create_if_not_exists index(:home_feed_entries, [:user_id, :id])
  end
end

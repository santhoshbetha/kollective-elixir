defmodule Kollective.Repo.Migrations.CreateHomeFeedEntries do
  use Ecto.Migration

  use Ecto.Migration

  def change do
    create table(:home_feed_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false # The timeline owner
      add :post_id, references(:posts, on_delete: :delete_all), null: false # The distributed post
      timestamps(type: :utc_datetime)
    end

    # Composite unique index ensures no duplicate posts slip into a timeline
    create unique_index(:home_feed_entries, [:user_id, :post_id])
    # Indexed for chronological cursor pagination sorting queries
    create index(:home_feed_entries, [:user_id, :id])
  end
end

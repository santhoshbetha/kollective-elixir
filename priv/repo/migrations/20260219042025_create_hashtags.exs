#  table for the tags and a join table to link them to posts.
defmodule Kollective.Repo.Migrations.CreateHashtags do
  use Ecto.Migration

  def change do
    # 1. The main Hashtags table
    create table(:hashtags) do
      add :name, :string, null: false
      timestamps()
    end

    # Crucial for the "get_or_create" logic and search speed
    create unique_index(:hashtags, [:name])

    # 2. The Join Table (The "Glue" between Posts and Hashtags)
    create table(:posts_hashtags, primary_key: false) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :hashtag_id, references(:hashtags, on_delete: :delete_all), null: false
    end

    create index(:posts_hashtags, [:post_id])
    create index(:posts_hashtags, [:hashtag_id])
    # Prevents linking the same hashtag to the same post twice
    create unique_index(:posts_hashtags, [:post_id, :hashtag_id])
  end
end

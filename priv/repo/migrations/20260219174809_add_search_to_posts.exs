#  to_tsvector('english', coalesce(content, '')) --> if only english is support in app

# tsvector column that automatically combines and tokenizes your content field. Using a generated
# column ensures the search index is always up-to-date without needing manual triggers.

defmodule Kollective.Repo.Migrations.AddSearchToPosts do
  use Ecto.Migration

  # lib/kollective/repo/migrations/add_search_to_posts.ex
  def change do
    alter table(:posts) do

      # Create a searchable column that uses the value in the 'language' column
      execute """
      ALTER TABLE posts
      ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
        to_tsvector(cast(language as regconfig), coalesce(content, ''))
      ) STORED;
      """
    end

    execute "CREATE INDEX posts_searchable_idx ON posts USING GIN(searchable);"
  end

end

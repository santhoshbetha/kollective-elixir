#  to_tsvector('english', coalesce(content, '')) --> if only english is support in app

# tsvector column that automatically combines and tokenizes your content field. Using a generated
# column ensures the search index is always up-to-date without needing manual triggers.
defmodule Kollective.Repo.Migrations.AddSearchToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # Keep this migration compatible whether fields exist in CreatePosts or not.
      add_if_not_exists :language, :string, default: "english", null: false
      add_if_not_exists :content, :text
    end

    # 1. Create a custom function marked as IMMUTABLE
    execute """
    CREATE OR REPLACE FUNCTION immutable_ts_regconfig(lang varchar)
    RETURNS regconfig AS $$
    BEGIN
      RETURN cast(coalesce(lang, 'english') as regconfig);
    EXCEPTION WHEN OTHERS THEN
      RETURN 'english'::regconfig;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # 2. Use that custom immutable function in your generated column definition
    execute """
    ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS searchable tsvector GENERATED ALWAYS AS (
      to_tsvector(immutable_ts_regconfig(language), coalesce(content, ''))
    ) STORED;
    """

    execute "CREATE INDEX IF NOT EXISTS posts_searchable_idx ON posts USING GIN(searchable);"
  end
end

# defmodule Kollective.Repo.Migrations.AddSearchToPosts do
##  use Ecto.Migration

##  def change do
##    alter table(:posts) do
##      add :language, :string, default: "english", null: false
##      add :content, :text
##    end

##    # Explicitly use 'english' text configuration to ensure immutability
##    execute """
##    ALTER TABLE posts
##    ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
##      to_tsvector('english', coalesce(content, ''))
##    ) STORED;
##    """

##    execute "CREATE INDEX posts_searchable_idx ON posts USING GIN(searchable);"
##  end
## end

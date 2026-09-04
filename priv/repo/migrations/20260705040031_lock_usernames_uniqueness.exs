defmodule Kollective.Repo.Migrations.LockUsernamesUniqueness do
  use Ecto.Migration

  def change do
    # Keep migration order resilient: only create the index when the column exists.
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'users' AND column_name = 'username'
        ) THEN
          CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_unique_index
            ON users ((lower(username)));
        END IF;
      END
      $$;
      """,
      "DROP INDEX IF EXISTS users_username_lower_unique_index;"
    )
  end
end

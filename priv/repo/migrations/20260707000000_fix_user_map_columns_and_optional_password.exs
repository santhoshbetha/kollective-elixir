defmodule Kollective.Repo.Migrations.FixUserMapColumnsAndOptionalPassword do
  use Ecto.Migration

  def up do
    # 1. Run raw SQL strings to safely handle the dynamic data type conversions
    execute "ALTER TABLE users ALTER COLUMN background TYPE jsonb USING background::jsonb;"
    execute "ALTER TABLE users ALTER COLUMN background SET DEFAULT '{}';"

    execute "ALTER TABLE users ALTER COLUMN emoji TYPE jsonb USING emoji::jsonb;"
    execute "ALTER TABLE users ALTER COLUMN emoji SET DEFAULT '{}';"

    # 2. Keep the simple structural change for password nullability
    alter table(:users) do
      modify :hashed_password, :string, null: true, from: {:string, null: false}
    end
  end

  def down do
    execute "ALTER TABLE users ALTER COLUMN background TYPE varchar USING background::text;"
    execute "ALTER TABLE users ALTER COLUMN emoji TYPE varchar USING emoji::text;"

    alter table(:users) do
      modify :hashed_password, :string, null: false, from: {:string, null: true}
    end
  end
end

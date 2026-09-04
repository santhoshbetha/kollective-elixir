defmodule Kollective.Repo.Migrations.CreateRestrictedKeywordsActive do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:restricted_keywords, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :word, :string, null: false
      add :is_active, :boolean, default: true, null: false
      add :action, :string, default: "pending", null: false
      add :level, :string, default: "soft", null: false
      add :weight, :integer, default: 1, null: false
      add :expires_at, :utc_datetime

      timestamps()
    end

    create_if_not_exists index(:restricted_keywords, [:level])

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS restricted_keywords_word_unique_index ON restricted_keywords ((lower(word)));",
      "DROP INDEX IF EXISTS restricted_keywords_word_unique_index;"
    )
  end
end

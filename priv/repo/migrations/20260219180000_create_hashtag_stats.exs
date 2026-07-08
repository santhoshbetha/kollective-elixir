# To make this work efficiently, you need a composite unique index on the hashtag_id and the bucket.
# This allows the database to perform high-speed "Upserts" (Update or Insert) every time a tag is used.

defmodule Kollective.Repo.Migrations.CreateHashtagStats do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:hashtag_stats) do
      add :count, :integer, default: 0, null: false
      add :bucket, :utc_datetime, null: false

      add :hashtag_id, references(:hashtags, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    # This index is critical for the trending algorithm's performance
    create_if_not_exists unique_index(:hashtag_stats, [:hashtag_id, :bucket])
    create_if_not_exists index(:hashtag_stats, [:bucket])
  end
end

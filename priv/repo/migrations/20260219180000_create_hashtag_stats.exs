#To make this work efficiently, you need a composite unique index on the hashtag_id and the bucket.
#This allows the database to perform high-speed "Upserts" (Update or Insert) every time a tag is used.

defmodule Kollective.Repo.Migrations.CreateHashtagStats do
  use Ecto.Migration

  def change do
    create table(:hashtag_stats) do
      add :count, :integer, default: 0, null: false
      add :bucket, :utc_datetime, null: false
      add :hashtag_id, references(:hashtags, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # This index is critical for the trending algorithm's performance
    create unique_index(:hashtag_stats, [:hashtag_id, :bucket])
    create index(:hashtag_stats, [:bucket])
  end
end

defmodule Kollective.Posts.HashtagStats do
  use Ecto.Schema

  schema "hashtag_stats" do
    field :count, :integer, default: 0
    field :bucket, :utc_datetime # Truncated to the hour

    belongs_to :hashtag, Kollective.Hashtags.Hashtag
  end

end

  # Index for fast lookups
 # create index(:hashtag_stats, [:bucket, :count])

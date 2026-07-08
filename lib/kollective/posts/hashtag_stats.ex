defmodule Kollective.Posts.HashtagStats do
  use Kollective.Schemas.Schema

  schema "hashtag_stats" do
    field :count, :integer, default: 0
    # Truncated to the hour
    field :bucket, :utc_datetime

    belongs_to :hashtag, Kollective.Hashtags.Hashtag
  end
end

# Index for fast lookups
# create index(:hashtag_stats, [:bucket, :count])

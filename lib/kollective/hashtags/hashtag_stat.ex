# This schema maps to a table that acts as a time-series log of hashtag activity.
defmodule Kollective.Hashtags.HashtagStat do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hashtag_stats" do
    field :count, :integer, default: 0
    # The 'bucket' represents the specific hour (e.g., 2024-05-20 14:00:00)
    field :bucket, :utc_datetime

    belongs_to :hashtag, Kollective.Hashtags.Hashtag

    timestamps(type: :utc_datetime)
  end

  def changeset(stat, attrs) do
    stat

    |> cast(attrs, [:count, :bucket, :hashtag_id])
    |> validate_required([:count, :bucket, :hashtag_id])
    # Ensure we don't have two records for the same tag in the same hour
    |> unique_constraint([:hashtag_id, :bucket])
  end
end

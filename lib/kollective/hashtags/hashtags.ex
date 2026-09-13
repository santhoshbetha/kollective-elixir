defmodule Kollective.Hashtags.Hashtags do
  @moduledoc """
  The Hashtags context.
  """

  import Ecto.Query, warn: false
  alias Kollective.Repo

  alias Kollective.Hashtags.Hashtag
  alias Kollective.Hashtags.HashtagStat

  def update_all_trending_scores do
    now = DateTime.utc_now()
    one_day_ago = DateTime.add(now, -24, :hour)
    seven_days_ago = DateTime.add(now, -7, :day)

    # 1. Reset old scores to 0 so dead trends disappear
    from(t in Hashtag, where: t.updated_at < ^one_day_ago)
    |> Repo.update_all(set: [trending_score: 0.0])

    # 2. Get active tags and their usage stats
    active_tags =
      from(s in HashtagStat,
        where: s.bucket >= ^seven_days_ago,
        group_by: s.hashtag_id,
        select: %{
          hashtag_id: s.hashtag_id,
          recent_count: filter(sum(s.count), s.bucket >= ^one_day_ago),
          weekly_total: sum(s.count)
        }
      )
      |> Repo.all()

    # 3. Calculate and update scores
    Enum.each(active_tags, fn stats ->
      score = calculate_hotness_score(stats.recent_count, stats.weekly_total)

      from(t in Hashtag, where: t.id == ^stats.hashtag_id)
      |> Repo.update_all(set: [trending_score: score])
    end)
  end

  # A simple "Velocity" algorithm
  defp calculate_hotness_score(recent, weekly_total) do
    daily_avg = weekly_total / 7.0
    # If recent usage is higher than the daily average, the score increases
    # We use :math.log to prevent massive spikes from breaking the scale
    if recent > daily_avg do
      :math.log(recent - daily_avg + 1)
    else
      0.0
    end
  end

  @doc """
  Returns the top trending hashtags based on their pre-calculated scores or usage stats.
  """
  def list_trending_tags(limit \\ 10) do
    from(h in Hashtag,
      left_join: s in HashtagStat,
      on: s.hashtag_id == h.id,
      group_by: [h.id, h.name],
      order_by: [desc: coalesce(sum(s.count), 0), desc: h.name],
      limit: ^limit,
      select: %{
        id: h.id,
        name: h.name,
        score: coalesce(sum(s.count), 0)
      }
    )
    |> Repo.all()
  end

  # How it's populated (The Upsert)
  # When a post is created, you don't just insert a row; you increment the count for the current hour's bucket.
  # This keeps the table size manageable
  def increment_hashtag_stat(hashtag_id) do
    now = DateTime.utc_now()

    # 🔄 FIX 1: Extract a clean %Date{} struct from the current time
    current_date = DateTime.to_date(now)

    # 🔄 FIX 2: Create an hour-aligned %Time{} struct forcing minutes/seconds to 0
    {:ok, aligned_time} = Time.new(now.hour, 0, 0)

    # 🔄 FIX 3: Combine them using native structs to satisfy type check boundaries
    {:ok, hour_bucket} = DateTime.new(current_date, aligned_time, "Etc/UTC")

    # Atomic Upsert: If the bucket exists, increment count. If not, create it.
    import Ecto.Query

    _query =
      from s in HashtagStat,
        where: s.hashtag_id == ^hashtag_id and s.bucket == ^hour_bucket

    Repo.insert!(
      %HashtagStat{hashtag_id: hashtag_id, bucket: hour_bucket, count: 1},
      on_conflict: [inc: [count: 1]],
      conflict_target: [:hashtag_id, :bucket]
    )
  end
end

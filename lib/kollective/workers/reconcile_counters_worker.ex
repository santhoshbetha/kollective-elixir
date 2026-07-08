# implement a nightly Data Reconciliation Cron Job using Oban to periodically verify that your counter
# caches haven't drifted from the raw UserRelationship counts
# This worker acts as a safety net. It runs a single high-performance SQL query to find any cached values that have
# shifted from the actual row counts in your relationships table and rewrites the incorrect totals instantly.
defmodule Kollective.Workers.ReconcileCountersWorker do
  use Oban.Worker, queue: :default, max_attempts: 1
  alias Kollective.Repo

  @impl Oban.Worker
  def perform(_job) do
    # Wrap both corrections in a single transaction block for stability
    Repo.transaction(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 1. SOFT EXPIRY RECONCILIATION LAYER
      # Finds voice posts whose expiry times have passed and sets deleted_at
      {:ok, _} =
        Repo.query(
          """
            UPDATE posts
            SET deleted_at = $1, updated_at = $1
            WHERE category = 'voice'
              AND expires_at IS NOT NULL
              AND expires_at <= $1
              AND deleted_at IS NULL;
          """,
          [now]
        )

      # 2. FIX FOLLOWER COUNTS
      # Calculates the exact counts from 'user_relationships' and updates the 'users' table
      {:ok, _} =
        Repo.query("""
          UPDATE users u
          SET followers_count = COALESCE(counts.actual_count, 0)
          FROM (
            SELECT target_id, COUNT(*) as actual_count
            FROM user_relationships
            WHERE type = 'follow'
            GROUP BY target_id
          ) counts
          WHERE u.id = counts.target_id AND u.followers_count != counts.actual_count;
        """)

      # 3. FIX FOLLOWING COUNTS
      {:ok, _} =
        Repo.query("""
          UPDATE users u
          SET following_count = COALESCE(counts.actual_count, 0)
          FROM (
            SELECT source_id, COUNT(*) as actual_count
            FROM user_relationships
            WHERE type = 'follow'
            GROUP BY source_id
          ) counts
          WHERE u.id = counts.source_id AND u.following_count != counts.actual_count;
        """)
    end)

    :ok
  end
end

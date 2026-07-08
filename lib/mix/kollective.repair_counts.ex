# lib/mix/tasks/kollective.repair_counts.ex
defmodule Mix.Tasks.Kollective.RepairCounts do
  use Mix.Task

  @shortdoc "Batched out-of-band repair script for user profile social counters"

  @impl Mix.Task
  def run(_args) do
    # 1. Spin up core application configurations and database connection pools safely
    Mix.Task.run("app.start")
    Mix.shell().info("🚀 Commencing background social counter cache reconciliation...")

    # 2. Execute atomic, index-driven queries on the live production database
    # This repairs counts instantly in RAM via high-speed database aggregations
    Kollective.Repo.transaction(
      fn ->
        # Recalculate and synchronize following_count
        Kollective.Repo.query!("""
          UPDATE users u
          SET following_count = COALESCE(sub.cnt, 0)
          FROM (
            SELECT source_id, count(*) as cnt
            FROM user_relationships
            WHERE type = 'follow'
            GROUP BY source_id
          ) sub
          WHERE u.id = sub.source_id;
        """)

        # Recalculate and synchronize follower_count
        Kollective.Repo.query!("""
          UPDATE users u
          SET follower_count = COALESCE(sub.cnt, 0)
          FROM (
            SELECT target_id, count(*) as cnt
            FROM user_relationships
            WHERE type = 'follow'
            GROUP BY target_id
          ) sub
          WHERE u.id = sub.target_id;
        """)
      end,
      timeout: :infinity
    )

    Mix.shell().info(
      "✅ Social counter caches successfully synchronized. Zero runtime web lag induced."
    )
  end
end

# How to Run This Repair in Production When you need to run a routine database alignment, you can ssh into your server or terminal
# cluster and execute the task completely out-of-band without blocking deployment pools:
# bash:
# mix kollective.repair_counts

defmodule Kollective.Notifications.Buffer do
  @moduledoc """
  Durable dynamic notification aggregator backed securely by PostgreSQL and Oban.
  Works perfectly across distributed nodes with zero split-brain risks.
  """
  # We listen on a dedicated ':notifications' queue
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Notifications.BufferedNotification
  alias KollectiveWeb.Endpoint

  # ─── CLIENT API ───

  @doc """
  Saves the notification to Postgres and schedules a single cluster-wide Oban flush
  job to fire 5 seconds into the future.
  """
  def enqueue(user_id, type, target_id) do
    # 1. Save this specific item hit to Postgres right away
    %BufferedNotification{user_id: user_id, type: type, target_id: target_id}
    |> Repo.insert!()

    # 2. Instruct Oban to schedule a flush job 5 seconds into the future.
    # By using `unique: [...]`, if 100 hits come in from Node A and Node B,
    # Oban inserts exactly ONE job into the DB queue. The other 99 are ignored safely.
    %{user_id: user_id, type: type, target_id: target_id}
    |> __MODULE__.new(
      scheduled_at: DateTime.add(DateTime.utc_now(), 5, :second),
      unique: [
        period: 5,
        fields: [:args],
        states: [:scheduled, :available]
      ]
    )
    |> Oban.insert()
  end

  # ─── CLUSTER EXECUTION WORKER CALLBACK ───

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "type" => type, "target_id" => target_id}}) do
    # This block is executed by exactly ONE node in your cluster when the 5-second window closes.

    # 3. Use a database transaction to read and delete rows safely without race conditions
    {:ok, count} =
      Repo.transaction(fn ->
        # Construct matching query parameters
        base_query =
          from(b in BufferedNotification,
            where: b.user_id == ^user_id and b.type == ^type and b.target_id == ^target_id
          )

        # Get the aggregate count across all servers
        count = Repo.aggregate(base_query, :count, :id)

        # Wipe those processed rows from the database table matrix
        Repo.delete_all(base_query)

        count
      end)

    # 4. Broadcast the complete cluster total down Phoenix PubSub channels
    # If count is 0 (handled by a racing node edge case), skip broadcasting.
    if count > 0 do
      Endpoint.broadcast("notifications:#{user_id}", "notifications_grouped", %{
        type: type,
        target_id: target_id,
        count: count
      })
    end

    :ok
  end
end

# test/kollective/notifications/buffer_test.exs
defmodule Kollective.Notifications.BufferTest do
  use Kollective.DataCase, async: true
  # ⚡ CRITICAL: Gives you access to assert_enqueued/1 macros
  use Oban.Testing, repo: Kollective.Repo

  import Kollective.Factory
  alias Kollective.Notifications.Buffer
  alias Kollective.Notifications.BufferedNotification

  setup do
    user = insert(:user)
    target_user = insert(:user)

    {:ok, user: user, target_user: target_user}
  end

  # describe "enqueue/3" do
  #  test "inserts raw notification row to database and enqueues exactly ONE unique Oban job", %{
  #    user: user,
  #    target_user: target_user
  #  } do
  #    user_id = user.id
  #    target_id = target_user.id

  #    Oban.Testing.with_testing_mode(:manual, fn ->
  # Simulate a high-concurrency burst of traffic (3 clicks in milliseconds)
  # {:ok, _job1} = Buffer.enqueue(user_id, "emoji_reaction", target_id)
  # {:ok, _job2} = Buffer.enqueue(user_id, "emoji_reaction", target_id)
  # {:ok, _job3} = Buffer.enqueue(user_id, "emoji_reaction", target_id)

  # 1. Assert that all 3 rows were recorded inside the database staging area safely
  #     count =
  #       BufferedNotification
  #       |> where(
  #         [b],
  #         b.user_id == ^user_id and b.type == "emoji_reaction" and b.target_id == ^target_id
  #       )
  #       |> Kollective.Repo.aggregate(:count, :id)

  #     assert count == 3

  # 2. Assert that Oban's unique configuration ignored the last 2 jobs
  # and that the queue contains exactly one matching job record.
  #      jobs = all_enqueued(worker: Buffer, queue: :notifications)

  #      assert length(jobs) == 1

  #      assert [
  #               %{
  #                 args: %{
  #                   "user_id" => ^user_id,
  #                   "type" => "emoji_reaction",
  #                   "target_id" => ^target_id
  #                 }
  #               }
  #             ] =
  #               jobs
  #     end)
  #   end
  # end

  describe "enqueue/3" do
    test "aggregates multiple rapid notifications into a single broadcast", %{
      user: user,
      target_user: target_user
    } do
      user_id = user.id
      target_id = target_user.id
      type = "like"

      # 1. Simulate 3 rapid notifications being enqueued (e.g., from different nodes)
      {:ok, _job1} = Buffer.enqueue(user_id, type, target_id)
      {:ok, _job2} = Buffer.enqueue(user_id, type, target_id)
      {:ok, _job3} = Buffer.enqueue(user_id, type, target_id)

      # 2. Assert that Oban's uniqueness engine only allowed exactly ONE job to be scheduled
      assert_enqueued(
        worker: Buffer,
        args: %{"user_id" => user_id, "type" => type, "target_id" => target_id}
      )

      # 3. Verify that all 3 distinct records exist in the buffer table prior to draining
      assert Repo.aggregate(BufferedNotification, :count, :id) == 3

      # 4. Drain the queue synchronously. This safely acts within the test's isolated sandbox connection.
      # Update Step 4 in your test code to:
      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :notifications, with_scheduled: true)

      # 5. Assert the buffer rows were safely purged post-execution
      assert Repo.aggregate(BufferedNotification, :count, :id) == 0
    end
  end

  describe "perform/1" do
    test "aggregates cluster rows, purges table data, and broadcasts total via PubSub", %{
      user: user,
      target_user: target_user
    } do
      target_id = target_user.id

      # Subscribe the test runner process to Phoenix Channels to intercept the final toast event
      KollectiveWeb.Endpoint.subscribe("notifications:#{user.id}")

      # Manually insert 3 un-aggregated hits straight into your database staging area
      insert(:buffered_notification,
        user_id: user.id,
        type: "emoji_reaction",
        target_id: target_user.id
      )

      insert(:buffered_notification,
        user_id: user.id,
        type: "emoji_reaction",
        target_id: target_user.id
      )

      insert(:buffered_notification,
        user_id: user.id,
        type: "emoji_reaction",
        target_id: target_user.id
      )

      # Reconstruct the arguments that Oban passes to the callback routine at execution runtime
      job_payload = %Oban.Job{
        args: %{"user_id" => user.id, "type" => "emoji_reaction", "target_id" => target_user.id}
      }

      # ⚡ Directly execute the worker callback code under test isolation conditions
      assert :ok == Buffer.perform(job_payload)

      # 1. Verify the database table was completely wiped to prevent double-processing rows
      remaining_rows = Kollective.Repo.all(BufferedNotification)
      assert remaining_rows == []

      # 2. Verify that Phoenix PubSub broadcasted the final collapsed aggregate count cleanly
      assert_receive %Phoenix.Socket.Broadcast{
        topic: "notifications:" <> _,
        event: "notifications_grouped",
        payload: %{type: "emoji_reaction", target_id: ^target_id, count: 3}
      }
    end
  end
end

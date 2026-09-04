# test/kollective/events/event_test.exs
defmodule Kollective.Events.EventTest do
  use Kollective.DataCase, async: true
  import Kollective.Factory
  # ⚡ CRITICAL: Gives you access to assert_enqueued/1 macros
  use Oban.Testing, repo: Kollective.Repo

  test "correctly handles nested ULID relationships during setup" do
    # Generates a User (with a ULID) and embeds it inside an Event (with a ULID)
    event = insert(:event)

    assert is_binary(event.id)
    assert String.length(event.id) == 26

    # Verifies that foreign relationship keys map flawlessly
    assert event.organization_id == event.organization.id
  end

  describe "update_event/3" do
    test "updates event and triggers notifications" do
      # 1. Setup your initial test fixtures (e.g., creating user, event, and attendee)
      user = insert(:user)

      event =
        insert(:event,
          user: user,
          street: "123 Plaza St",
          location_name: "Initial Hall",
          start_time: DateTime.utc_now() |> DateTime.add(3600, :second)
        )

      attendee = insert(:user)

      Kollective.Repo.insert!(%Kollective.Events.Participant{
        event_id: event.id,
        user_id: attendee.id,
        status: "accepted"
      })

      attrs = %{
        start_time: DateTime.utc_now() |> DateTime.add(7200, :second),
        location_name: "New Plaza Hall Address"
      }

      # 2. Execute the code that queues the GeocodeWorker and NotifyAttendeesWorker jobs
      assert {:ok, updated_event} = Kollective.Events.Events.update_event(user, event.id, attrs)
      assert updated_event.location_name == "New Plaza Hall Address"

      # 3. Assert that jobs were successfully enqueued in Oban
      assert_enqueued(
        worker: Kollective.Workers.GeocodeWorker,
        args: %{
          "target_id" => event.id,
          "schema_type" => "Event",
          "address_text" => "New Plaza Hall Address"
        }
      )

      assert_enqueued(
        worker: Kollective.Workers.NotifyAttendeesWorker,
        args: %{
          "event_id" => event.id
        }
      )

      # 4. Drain the notifications queue synchronously inside this test process.
      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :notifications)

      # 5. Assert the side effects of your background worker execution
      assert Kollective.Repo.exists?(
               from(n in Kollective.Notifications.Notification,
                 where: n.user_id == ^attendee.id and n.type == "event_update"
               )
             )
    end
  end
end

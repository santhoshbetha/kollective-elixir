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

  describe "list_nearby_events" do
    test "fetches events within given radius using user coordinates and explicit coordinates" do
      # Setup user with Austin location: 30.2672, -97.7431
      user =
        insert(:user,
          location: "POINT(-97.7431 30.2672)"
        )

      # Austin event (~0 miles)
      austin_event =
        insert(:event,
          title: "Austin Music Fest",
          latitude: 30.2672,
          longitude: -97.7431,
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326},
          event_status: "published",
          user: user
        )

      # Round Rock event (~15 miles)
      rr_event =
        insert(:event,
          title: "Round Rock Tech Talk",
          latitude: 30.5083,
          longitude: -97.6789,
          location: %Geo.Point{coordinates: {-97.6789, 30.5083}, srid: 4326},
          event_status: "published"
        )

      # Houston event (~160 miles: 29.7604, -95.3698)
      houston_event =
        insert(:event,
          title: "Houston Art Walk",
          latitude: 29.7604,
          longitude: -95.3698,
          location: %Geo.Point{coordinates: {-95.3698, 29.7604}, srid: 4326},
          event_status: "published"
        )

      # 1. list_nearby_events(user, %{"radius" => "5"}) -> Austin only
      events_5 = Kollective.Events.Events.list_nearby_events(user, %{"radius" => "5"})
      ids_5 = Enum.map(events_5, & &1.id)
      assert austin_event.id in ids_5
      refute rr_event.id in ids_5
      refute houston_event.id in ids_5

      # 2. list_nearby_events(user, %{"radius" => "25"}) -> Austin and Round Rock
      events_25 = Kollective.Events.Events.list_nearby_events(user, %{"radius" => "25"})
      ids_25 = Enum.map(events_25, & &1.id)
      assert austin_event.id in ids_25
      assert rr_event.id in ids_25
      refute houston_event.id in ids_25

      # 3. list_nearby_events(lat, lng, radius_meters) -> explicit coordinates
      events_coords = Kollective.Events.Events.list_nearby_events(30.2672, -97.7431, 40_000)
      ids_coords = Enum.map(events_coords, & &1.id)
      assert austin_event.id in ids_coords
      assert rr_event.id in ids_coords
      refute houston_event.id in ids_coords

      # Distance meters metadata is populated
      austin_res = Enum.find(events_25, &(&1.id == austin_event.id))
      assert is_number(austin_res.metadata["distance_meters"])
    end
  end
end

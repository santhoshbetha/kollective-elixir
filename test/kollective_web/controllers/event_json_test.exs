defmodule KollectiveWeb.EventJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.User
  alias Kollective.Events.{Event, Participant}
  alias Kollective.Locations.City
  alias KollectiveWeb.EventJSON

  describe "EventJSON serialization" do
    setup do
      user_id = Ecto.ULID.generate()

      user = %User{
        id: user_id,
        username: "organizer_jane",
        display_name: "Jane Organizer",
        avatar_url: "https://example.com/jane.png",
        is_verified: true,
        inserted_at: ~U[2026-01-01 00:00:00Z]
      }

      city = %City{
        id: 7,
        name: "Austin"
      }

      now = ~U[2026-06-01 18:00:00Z]
      later = ~U[2026-06-01 20:00:00Z]

      event = %Event{
        id: 101,
        title: "Community Town Hall",
        description: "Discussing local infrastructure",
        start_time: now,
        end_time: later,
        timezone: "America/Chicago",
        event_status: "published",
        banner_url: "https://example.com/banner.png",
        logo_url: "https://example.com/logo.png",
        participants_count: 50,
        comments_count: 12,
        location_name: "City Hall Main Auditorium",
        street: "301 W 2nd St",
        origin_city: city,
        origin_state: "TX",
        origin_country: "US",
        origin_district_l1: nil,
        origin_district_l2: nil,
        origin_district_l3: nil,
        user: user,
        inserted_at: ~U[2026-05-15 12:00:00Z]
      }

      {:ok, user: user, city: city, event: event}
    end

    test "data/1 serializes full event entity", %{event: event, user: user} do
      data = EventJSON.data(event)

      assert data.id == 101
      assert data.title == "Community Town Hall"
      assert data.description == "Discussing local infrastructure"
      assert data.start_time == ~U[2026-06-01 18:00:00Z]
      assert data.end_time == ~U[2026-06-01 20:00:00Z]
      assert data.timezone == "America/Chicago"
      assert data.status == "published"
      assert data.banner_url == "https://example.com/banner.png"
      assert data.logo_url == "https://example.com/logo.png"
      assert data.participants_count == 50
      assert data.comments_count == 12

      assert data.location.name == "City Hall Main Auditorium"
      assert data.location.city == "Austin"
      assert data.location.address == "301 W 2nd St"
      assert data.location.state == "TX"
      assert data.location.country == "US"
      assert data.location.district_l1 == nil

      assert data.organizer.id == user.id
      assert data.organizer.username == "organizer_jane"
      assert data.organizer.is_verified == true
      assert data.inserted_at == ~U[2026-05-15 12:00:00Z]
    end

    test "data/1 safely handles missing or not loaded user and city", %{event: event} do
      event_unloaded = %{
        event
        | user: %Ecto.Association.NotLoaded{},
          origin_city: %Ecto.Association.NotLoaded{}
      }

      data = EventJSON.data(event_unloaded)

      assert data.organizer == nil
      assert data.location.city == nil
    end

    test "index/1 wraps list in %{data: [...] }", %{event: event} do
      result = EventJSON.index(%{events: [event]})

      assert is_list(result.data)
      assert length(result.data) == 1
      assert hd(result.data).id == 101
    end

    test "show/1 returns %{data: ...}", %{event: event} do
      result = EventJSON.show(%{event: event})

      assert result.data.id == 101
      assert result.data.title == "Community Town Hall"
    end

    test "simple_participant/1 serializes participant preview", %{user: user} do
      participant = %Participant{
        id: 1,
        user: user
      }

      result = EventJSON.simple_participant(participant)

      assert result.id == user.id
      assert result.username == "organizer_jane"
      assert result.avatar_url == "https://example.com/jane.png"
    end

    test "event_with_social_context/3 combines event, preview, and friends", %{
      event: event,
      user: user
    } do
      participant = %Participant{id: 1, user: user}

      result = EventJSON.event_with_social_context(event, [participant], [participant])

      assert result.event.id == 101
      assert length(result.attendee_preview) == 1
      assert hd(result.attendee_preview).username == "organizer_jane"
      assert length(result.friends_attending) == 1
      assert hd(result.friends_attending).username == "organizer_jane"
    end

    test "participant_users/1 and participant_user/1 serialize user rosters", %{user: user} do
      users_data = EventJSON.participant_users([user])

      assert length(users_data) == 1
      user_data = hd(users_data)

      assert user_data.id == user.id
      assert user_data.username == "organizer_jane"
      assert user_data.display_name == "Jane Organizer"
      assert user_data.avatar_url == "https://example.com/jane.png"
    end

    test "actions/1, action_item/1, and action_data/1 serialize collective actions", %{
      event: event,
      user: _user
    } do
      action_event = %{
        event
        | category: "protest",
          participation_format: "in_person",
          organization_id: 99
      }

      items = EventJSON.actions([action_event])
      assert length(items) == 1

      item = hd(items)
      assert item.id == "101"
      assert item.name == "Community Town Hall"
      assert item.category == "protest"
      assert item.participation_format == "in_person"
      assert item.is_official == true
      assert item.initiator == "organizer_jane"

      summary = EventJSON.action_data(action_event)
      assert summary.id == "101"
      assert summary.name == "Community Town Hall"
      assert summary.category == "protest"
    end

    test "participation_requests/1 serializes pending requests", %{user: user} do
      request = %Participant{
        id: 201,
        status: "pending",
        user: user,
        inserted_at: ~U[2026-06-01 12:00:00Z]
      }

      requests = EventJSON.participation_requests(%{requests: [request], for: user})

      assert length(requests) == 1
      req = hd(requests)
      assert req.id == "201"
      assert req.type == "participation_request"
      assert req.state == "pending"
      assert req.created_at == "2026-06-01T12:00:00Z"
      assert req.account.username == "organizer_jane"
    end
  end
end

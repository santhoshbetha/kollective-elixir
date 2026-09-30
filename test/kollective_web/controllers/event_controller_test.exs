defmodule KollectiveWeb.EventControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory
  import Req.Test

  alias Kollective.Moderation.RestrictedKeyword
  alias Kollective.Repo

  setup %{conn: conn} do
    stub(Kollective.Services.GeocodioClient, fn conn ->
      json(conn, %{
        "results" => [%{"response" => %{"input" => %{}}, "response_status" => "success"}]
      })
    end)

    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "authentication" do
    test "GET /api/v1/events returns 401 for unauthenticated requests" do
      conn = build_conn() |> get(~p"/api/v1/events")
      assert conn.status == 401
    end
  end

  describe "index/2" do
    test "returns a serialized list for authenticated requests", %{conn: conn, user: user} do
      _event = insert(:event, created_by: user.id, user: user, join_mode: "free")

      response = conn |> get(~p"/api/v1/events") |> json_response(200)

      assert is_list(response["data"])
    end
  end

  describe "show/2" do
    test "injects user RSVP state metadata", %{conn: conn, user: user} do
      event =
        insert(:event,
          created_by: user.id,
          user: user,
          organization: user,
          title: "Phoenix Framework Summit"
        )

      insert(:participant, event: event, user: user, status: "accepted")

      response = conn |> get(~p"/api/v1/events/#{event.id}") |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == event.id
      assert response["data"]["join_state"] == "accepted"
    end
  end

  describe "joined_events/2" do
    test "returns list of events joined by current user", %{conn: conn, user: user} do
      event = insert(:event, created_by: user.id, user: user)
      insert(:participant, event: event, user: user, status: "accepted")

      response = conn |> get(~p"/api/v1/events/joined") |> json_response(200)

      assert is_list(response["data"])
    end
  end

  describe "invite/2" do
    test "successfully invites a user to an event", %{conn: conn, user: user} do
      target_user = insert(:user)
      event = insert(:event, created_by: user.id, user: user, join_mode: "free")

      response =
        conn
        |> post(~p"/api/v1/events/#{event.id}/invite", %{"user_id" => target_user.id})
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "Invitation sent successfully"
    end

    test "returns 403 forbidden if non-organizer invites to invite_only event", %{conn: conn} do
      other_user = insert(:user)
      target_user = insert(:user)

      event =
        insert(:event, created_by: other_user.id, user: other_user, join_mode: "invite_only")

      response =
        conn
        |> post(~p"/api/v1/events/#{event.id}/invite", %{"user_id" => target_user.id})
        |> json_response(403)

      assert response["error"] == "forbidden"
    end
  end

  describe "create/2" do
    test "successfully creates event", %{conn: conn} do
      params = %{
        "event" => %{
          "title" => "Legitimate Protests Rally",
          "description" => "A peaceful civic gathering.",
          "category" => "standard",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "location_name" => "Community Center Main Hall",
          "street" => "123 Civic Plaza",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
        }
      }

      response = conn |> post(~p"/api/v1/events", params) |> json_response(201)
      assert response["status"] == "success"
      assert response["data"]["title"] == "Legitimate Protests Rally"
    end

    test "successfully creates event from frontend flat payload with format, date, time, capacity, and image",
         %{conn: conn} do
      params = %{
        "title" => "Austin Tech Collaborative",
        "description" => "Building decentralized tech for community resilience.",
        "format" => "In-Person",
        "category" => "Technology",
        "date" => "Jun 20, 2026",
        "time" => "14:00 - 17:00",
        "location" => "Austin Public Library, 710 W Cesar Chavez St",
        "capacity" => 150,
        "image" => "https://example.com/cover.jpg"
      }

      response = conn |> post(~p"/api/v1/events", params) |> json_response(201)
      assert response["status"] == "success"
      data = response["data"]
      assert data["title"] == "Austin Tech Collaborative"
      assert data["category"] == "Technology"
      assert data["format"] == "In-Person"
      assert data["participation_format"] == "in_person"
      assert data["capacity"] == 150
      assert data["image"] == "https://example.com/cover.jpg"
      assert data["location_name"] == "Austin Public Library, 710 W Cesar Chavez St"
      assert data["start_time"] != nil
    end

    test "returns 422 on first hard-ban strike", %{conn: conn} do
      banned_word = insert_hard_keyword()

      params = %{
        "event" => %{
          "title" => "Malicious Attempt #{banned_word}",
          "description" => "contains #{banned_word}",
          "category" => "standard",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
        }
      }

      response = conn |> post(~p"/api/v1/events", params) |> json_response(422)

      assert response["error"] == "Your post contains prohibited language."
    end
  end

  defp insert_hard_keyword do
    word = "blocked_event_#{System.unique_integer([:positive])}"

    %RestrictedKeyword{}
    |> RestrictedKeyword.changeset(%{
      word: word,
      level: "hard",
      action: "reject",
      is_active: true
    })
    |> Repo.insert!()

    word
  end

  describe "update/2" do
    setup %{user: user} do
      # Pre-seed an event owned by our authenticated test user
      start_time = DateTime.utc_now() |> DateTime.add(1800, :second)

      event =
        insert(:event,
          created_by: user.id,
          user: user,
          organization: user,
          title: "Original Title",
          start_time: start_time,
          end_time: DateTime.add(start_time, 3600, :second),
          event_status: "published"
        )

      {:ok, event: event}
    end

    test "successfully updates event", %{
      conn: conn,
      event: event
    } do
      params = %{
        "event" => %{
          "title" => "Updated Legitimate Title",
          "description" => "An updated peaceful community gathering.",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
          "location_name" => "Community Center Main Hall",
          "street" => "123 Civic Plaza"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{event.id}", params) |> json_response(200)
      assert response["status"] == "success"
      assert response["data"]["title"] == "Updated Legitimate Title"
    end

    test "returns 403 forbidden if a user attempts to update someone else's event", %{conn: conn} do
      # Create an event owned by a completely different user
      other_user = insert(:user)
      other_event = insert(:event, created_by: other_user.id, user: other_user)

      params = %{
        "event" => %{
          "title" => "Malicious Hijack Attempt"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{other_event.id}", params) |> json_response(403)
      assert response["error"] == "You are not authorized to edit this event."
    end

    test "returns 422 unprocessable entity on the first hard-ban strike inside edits", %{
      conn: conn,
      event: event
    } do
      banned_word = insert_hard_keyword()

      params = %{
        "event" => %{
          "title" => "Malicious Edit #{banned_word}"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{event.id}", params) |> json_response(422)
      assert response["error"] == "Your edits contain prohibited language."
    end
  end

  describe "delete/2" do
    test "successfully cancels an event if the requester is the original owner", %{
      conn: conn,
      user: user
    } do
      event = insert(:event, created_by: user.id, user: user)

      response = conn |> delete(~p"/api/v1/events/#{event.id}") |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "successfully deleted"
    end

    test "returns 403 forbidden if a user attempts to delete an event they do not own", %{
      conn: conn
    } do
      other_user = insert(:user)
      other_event = insert(:event, created_by: other_user.id, user: other_user)

      response = conn |> delete(~p"/api/v1/events/#{other_event.id}") |> json_response(403)

      assert response["error"] == "unauthorized"
      assert response["message"] =~ "You don't own this event"
    end
  end

  describe "nearby/2" do
    test "GET /api/v1/events/nearby returns 401 for unauthenticated requests" do
      conn = build_conn() |> get(~p"/api/v1/events/nearby")
      assert conn.status == 401
    end

    test "returns nearby published events within given radius", %{conn: conn, user: user} do
      # User location in Austin: lat: 30.2672, lng: -97.7431
      {:ok, user} =
        Repo.update(
          Ecto.Changeset.change(user, %{
            location: "POINT(-97.7431 30.2672)"
          })
        )

      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, %{user: user})

      # Event 1: In Austin (~0 miles away)
      austin_event =
        insert(:event,
          title: "Austin Town Hall",
          latitude: 30.2672,
          longitude: -97.7431,
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326},
          event_status: "published",
          user: user
        )

      # Event 2: In Round Rock (~15 miles away: 30.5083, -97.6789)
      round_rock_event =
        insert(:event,
          title: "Round Rock Community Meet",
          latitude: 30.5083,
          longitude: -97.6789,
          location: %Geo.Point{coordinates: {-97.6789, 30.5083}, srid: 4326},
          event_status: "published"
        )

      # Event 3: In Dallas (~195 miles away: 32.7767, -96.7970)
      dallas_event =
        insert(:event,
          title: "Dallas Rally",
          latitude: 32.7767,
          longitude: -96.7970,
          location: %Geo.Point{coordinates: {-96.7970, 32.7767}, srid: 4326},
          event_status: "published"
        )

      # 1. Radius: 5 miles -> only Austin event
      res5 = conn |> get(~p"/api/v1/events/nearby?radius=5") |> json_response(200)
      ids5 = Enum.map(res5["data"], & &1["id"])
      assert austin_event.id in ids5
      refute round_rock_event.id in ids5
      refute dallas_event.id in ids5

      # 2. Radius: 25 miles -> Austin & Round Rock events, Dallas excluded
      res25 = conn |> get(~p"/api/v1/events/nearby?radius=25") |> json_response(200)
      ids25 = Enum.map(res25["data"], & &1["id"])
      assert austin_event.id in ids25
      assert round_rock_event.id in ids25
      refute dallas_event.id in ids25

      # 3. Radius: 250 miles -> all events included
      res250 = conn |> get(~p"/api/v1/events/nearby?radius=250") |> json_response(200)
      ids250 = Enum.map(res250["data"], & &1["id"])
      assert austin_event.id in ids250
      assert round_rock_event.id in ids250
      assert dallas_event.id in ids250

      # 4. Explicit coordinates passed in query params
      res_coords =
        conn
        |> get(~p"/api/v1/events/nearby?lat=30.5083&lng=-97.6789&radius=10")
        |> json_response(200)

      ids_coords = Enum.map(res_coords["data"], & &1["id"])
      assert round_rock_event.id in ids_coords
      refute dallas_event.id in ids_coords
    end

    test "uses user's stored fuzzy coordinates when no parameters are provided", %{conn: conn} do
      fuzzy_user = insert(:user, location: "POINT(-97.74 30.27)")

      event =
        insert(:event,
          title: "Austin Downtown Meetup",
          latitude: 30.2672,
          longitude: -97.7431,
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326},
          event_status: "published"
        )

      conn =
        conn
        |> assign(:current_user, fuzzy_user)
        |> assign(:current_scope, %{user: fuzzy_user})

      response = conn |> get(~p"/api/v1/events/nearby") |> json_response(200)
      ids = Enum.map(response["data"], & &1["id"])
      assert event.id in ids
    end
  end
end

defmodule KollectiveWeb.EventParticipantControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Events.Participant

  setup %{conn: conn} do
    u = fn attrs ->
      id = System.unique_integer([:positive])

      insert(
        :user,
        Map.merge(
          %{
            email: "evp_#{id}@test.com",
            username: "evp_#{id}",
            identity_hash: "hash_#{id}"
          },
          Map.new(attrs)
        )
      )
    end

    organizer = u.([])
    attendee = u.([])
    other_user = u.([])

    event =
      insert(:event,
        created_by: organizer.id,
        user: organizer,
        organization: organizer,
        join_mode: "free",
        title: "Community Townhall"
      )

    req_event =
      insert(:event,
        created_by: organizer.id,
        user: organizer,
        organization: organizer,
        join_mode: "request",
        title: "Private Planning Session"
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:is_authenticated, true)

    {:ok,
     conn: conn,
     organizer: organizer,
     attendee: attendee,
     other_user: other_user,
     event: event,
     req_event: req_event}
  end

  describe "POST /api/v1/events/:event_id/join" do
    test "joins a free event successfully", %{conn: conn, attendee: attendee, event: event} do
      conn =
        conn
        |> assign(:current_user, attendee)
        |> assign(:user, attendee)
        |> post(~p"/api/v1/events/#{event.id}/join")

      assert %{"status" => "success", "code" => code} = json_response(conn, 200)
      assert code in ["joined", "left", "waitlisted", "requested"]
    end
  end

  describe "POST /api/v1/events/:event_id/leave" do
    test "leaves an event successfully", %{conn: conn, attendee: attendee, event: event} do
      # First ensure user joined
      insert(:participant, event: event, user: attendee, status: "accepted")

      conn =
        conn
        |> assign(:current_user, attendee)
        |> assign(:user, attendee)
        |> post(~p"/api/v1/events/#{event.id}/leave")

      assert %{"status" => "success", "message" => msg} = json_response(conn, 200)
      assert msg =~ "Successfully left"
    end
  end

  describe "POST /api/v1/events/:event_id/rsvp" do
    test "updates rsvp to going", %{conn: conn, attendee: attendee, event: event} do
      conn =
        conn
        |> assign(:current_user, attendee)
        |> assign(:user, attendee)
        |> post(~p"/api/v1/events/#{event.id}/rsvp", %{"status" => "going"})

      assert %{"status" => "success"} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/events/:event_id/participants" do
    test "lists accepted participants", %{conn: conn, attendee: attendee, event: event} do
      insert(:participant, event: event, user: attendee, status: "accepted")

      conn =
        conn
        |> assign(:current_user, attendee)
        |> assign(:user, attendee)
        |> get(~p"/api/v1/events/#{event.id}/participants")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert Enum.any?(data, &(&1["id"] == attendee.id))
    end
  end

  describe "Participation requests approval/rejection" do
    test "organizer can list pending requests", %{
      conn: conn,
      organizer: organizer,
      attendee: attendee,
      req_event: req_event
    } do
      insert(:participant, event: req_event, user: attendee, status: "pending")

      conn =
        conn
        |> assign(:current_user, organizer)
        |> assign(:user, organizer)
        |> get(~p"/api/v1/events/#{req_event.id}/requests")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert length(data) >= 1
    end

    test "non-organizer cannot view requests", %{
      conn: conn,
      other_user: other_user,
      req_event: req_event
    } do
      conn =
        conn
        |> assign(:current_user, other_user)
        |> assign(:user, other_user)
        |> get(~p"/api/v1/events/#{req_event.id}/requests")

      assert json_response(conn, 403)["error"] =~ "not authorized"
    end

    test "organizer can approve a request", %{
      conn: conn,
      organizer: organizer,
      attendee: attendee,
      req_event: req_event
    } do
      part = insert(:participant, event: req_event, user: attendee, status: "pending")

      conn =
        conn
        |> assign(:current_user, organizer)
        |> assign(:user, organizer)
        |> post(~p"/api/v1/events/requests/#{part.id}/approve")

      assert %{"status" => "success", "message" => msg} = json_response(conn, 200)
      assert msg =~ "approved"

      updated = Repo.get!(Participant, part.id)
      assert updated.status == "accepted"
    end

    test "organizer can reject a request", %{
      conn: conn,
      organizer: organizer,
      attendee: attendee,
      req_event: req_event
    } do
      part = insert(:participant, event: req_event, user: attendee, status: "pending")

      conn =
        conn
        |> assign(:current_user, organizer)
        |> assign(:user, organizer)
        |> post(~p"/api/v1/events/requests/#{part.id}/reject")

      assert %{"status" => "success", "message" => msg} = json_response(conn, 200)
      assert msg =~ "rejected"

      assert Repo.get(Participant, part.id) == nil
    end
  end
end

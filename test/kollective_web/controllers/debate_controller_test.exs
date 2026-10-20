defmodule KollectiveWeb.DebateControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Campaigns.{DebateEvent, DebateShift}

  setup %{conn: conn} do
    u = fn attrs ->
      id = System.unique_integer([:positive])

      insert(
        :user,
        Map.merge(
          %{
            email: "debate_#{id}@test.com",
            username: "debater_#{id}",
            identity_hash: "hash_#{id}"
          },
          Map.new(attrs)
        )
      )
    end

    user1 = u.([])
    user2 = u.([])
    user3 = u.([])

    unique_code = "TX-#{System.unique_integer([:positive])}"

    event =
      %DebateEvent{}
      |> Ecto.Changeset.change(%{
        title: "Congressional District Debate",
        date_time: DateTime.utc_now() |> DateTime.truncate(:second),
        venue_address: "100 Main St, Austin, TX",
        office_level: "congress",
        district_code: unique_code,
        broadcast_node_url: "https://stream.kollective.org/tx-10"
      })
      |> Repo.insert!()

    shift =
      %DebateShift{}
      |> Ecto.Changeset.change(%{
        role_name: "AV Technician",
        max_volunteers: 2,
        debate_event_id: event.id
      })
      |> Repo.insert!()

    single_seat_shift =
      %DebateShift{}
      |> Ecto.Changeset.change(%{
        role_name: "Moderator Assistant",
        max_volunteers: 1,
        debate_event_id: event.id
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:is_authenticated, true)

    {:ok,
     conn: conn,
     user1: user1,
     user2: user2,
     user3: user3,
     unique_code: unique_code,
     event: event,
     shift: shift,
     single_seat_shift: single_seat_shift}
  end

  describe "GET /api/v1/campaigns/debates" do
    test "returns debates filtered by level and district code", %{
      conn: conn,
      user1: user1,
      unique_code: code,
      event: event
    } do
      conn =
        conn
        |> assign(:current_user, user1)
        |> assign(:user, user1)
        |> get(~p"/api/v1/campaigns/debates", %{"level" => "congress", "code" => code})

      assert response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["id"] == event.id
      assert hd(response)["district_code"] == code
      assert length(hd(response)["shifts"]) == 2
    end
  end

  describe "POST /api/v1/campaigns/debates/shifts/:id/claim" do
    test "successfully claims a volunteer shift slot", %{
      conn: conn,
      user1: user1,
      shift: shift
    } do
      conn =
        conn
        |> assign(:current_user, user1)
        |> assign(:user, user1)
        |> post(~p"/api/v1/campaigns/debates/shifts/#{shift.id}/claim")

      assert %{"id" => id, "volunteers" => volunteers} = json_response(conn, 200)
      assert id == shift.id
      assert Enum.any?(volunteers, &(&1["id"] == user1.id))
    end

    test "returns 409 conflict when user already claimed the shift", %{
      conn: conn,
      user1: user1,
      shift: shift
    } do
      conn1 =
        conn
        |> assign(:current_user, user1)
        |> assign(:user, user1)

      conn1 |> post(~p"/api/v1/campaigns/debates/shifts/#{shift.id}/claim")

      conn2 =
        conn
        |> assign(:current_user, user1)
        |> assign(:user, user1)
        |> post(~p"/api/v1/campaigns/debates/shifts/#{shift.id}/claim")

      assert json_response(conn2, 409)["error"] =~ "already catalogued"
    end

    test "returns 422 when shift reaches capacity", %{
      conn: conn,
      user1: user1,
      user2: user2,
      single_seat_shift: shift
    } do
      # User 1 takes the only slot
      conn
      |> assign(:current_user, user1)
      |> assign(:user, user1)
      |> post(~p"/api/v1/campaigns/debates/shifts/#{shift.id}/claim")

      # User 2 tries to claim the same shift
      conn2 =
        conn
        |> assign(:current_user, user2)
        |> assign(:user, user2)
        |> post(~p"/api/v1/campaigns/debates/shifts/#{shift.id}/claim")

      assert json_response(conn2, 422)["error"] =~ "reached maximum volunteer capacity"
    end
  end
end

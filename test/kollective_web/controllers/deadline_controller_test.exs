defmodule KollectiveWeb.DeadlineControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Campaigns.ElectionDeadline

  setup %{conn: conn} do
    u = fn attrs ->
      id = System.unique_integer([:positive])
      insert(:user, Map.merge(%{
        email: "deadline_#{id}@test.com",
        username: "deadline_#{id}",
        identity_hash: "hash_#{id}"
      }, Map.new(attrs)))
    end

    admin_user = u.(role: :admin, is_admin: true)
    verified_candidate = u.(is_verified_candidate: true)
    regular_user = u.(is_admin: false, is_moderator: false, role: :user)

    unique_state = "S#{System.unique_integer([:positive])}"

    deadline1 =
      %ElectionDeadline{}
      |> ElectionDeadline.changeset(%{
        office_level: "municipal",
        district_code: "austin_tx",
        sub_local_name: "City Council Place 1",
        application_deadline: ~D[2026-08-01],
        election_date: ~D[2026-11-03],
        state: unique_state,
        logged_by_id: admin_user.id
      })
      |> Repo.insert!()

    deadline2 =
      %ElectionDeadline{}
      |> ElectionDeadline.changeset(%{
        office_level: "municipal",
        district_code: "houston_tx",
        sub_local_name: "Mayor",
        application_deadline: ~D[2026-08-15],
        election_date: ~D[2026-11-03],
        state: unique_state,
        logged_by_id: admin_user.id
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:is_authenticated, true)

    {:ok,
     conn: conn,
     admin_user: admin_user,
     verified_candidate: verified_candidate,
     regular_user: regular_user,
     unique_state: unique_state,
     deadline1: deadline1,
     deadline2: deadline2}
  end

  describe "GET /api/v1/campaigns/deadlines" do
    test "lists deadlines filtered by district code", %{conn: conn, admin_user: admin_user, unique_state: state, deadline1: d1} do
      conn =
        conn
        |> assign(:current_user, admin_user)
        |> assign(:user, admin_user)
        |> get(~p"/api/v1/campaigns/deadlines", %{
          "state" => state,
          "level" => "municipal",
          "code" => "austin_tx"
        })

      assert response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["id"] == d1.id
      assert hd(response)["district_code"] == "austin_tx"
    end

    test "lists all deadlines for state and level when code is 'all'", %{conn: conn, admin_user: admin_user, unique_state: state} do
      conn =
        conn
        |> assign(:current_user, admin_user)
        |> assign(:user, admin_user)
        |> get(~p"/api/v1/campaigns/deadlines", %{
          "state" => state,
          "level" => "municipal",
          "code" => "all"
        })

      assert response = json_response(conn, 200)
      assert length(response) == 2
    end
  end

  describe "POST /api/v1/campaigns/deadlines" do
    test "allows authorized user (verified candidate) to create deadline", %{
      conn: conn,
      verified_candidate: candidate
    } do
      params = %{
        "deadline" => %{
          "office_level" => "county",
          "district_code" => "travis_county",
          "sub_local_name" => "County Judge",
          "application_deadline" => "2026-09-01",
          "election_date" => "2026-11-03",
          "state" => "TX"
        }
      }

      conn =
        conn
        |> assign(:current_user, candidate)
        |> assign(:user, candidate)
        |> post(~p"/api/v1/campaigns/deadlines", params)

      assert %{"id" => id, "district_code" => "travis_county"} = json_response(conn, 201)
      assert Repo.get(ElectionDeadline, id) != nil
    end

    test "returns 422 if deadline follows election date", %{
      conn: conn,
      admin_user: admin_user
    } do
      params = %{
        "deadline" => %{
          "office_level" => "county",
          "district_code" => "dallas_county",
          "sub_local_name" => "Sheriff",
          "application_deadline" => "2026-12-01",
          "election_date" => "2026-11-03",
          "state" => "TX"
        }
      }

      conn =
        conn
        |> assign(:current_user, admin_user)
        |> assign(:user, admin_user)
        |> post(~p"/api/v1/campaigns/deadlines", params)

      assert %{"errors" => %{"application_deadline" => [msg]}} = json_response(conn, 422)
      assert msg =~ "Application cutoff deadline cannot follow"
    end

    test "returns 401 for unauthorized regular user", %{
      conn: conn,
      regular_user: regular_user
    } do
      params = %{
        "deadline" => %{
          "office_level" => "county",
          "district_code" => "travis_county",
          "application_deadline" => "2026-09-01",
          "election_date" => "2026-11-03",
          "state" => "TX"
        }
      }

      conn =
        conn
        |> assign(:current_user, regular_user)
        |> assign(:user, regular_user)
        |> post(~p"/api/v1/campaigns/deadlines", params)

      assert json_response(conn, 401)["error"] =~ "credentials lack authorized ledger writer status"
    end
  end
end

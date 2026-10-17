defmodule KollectiveWeb.DistrictControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Req.Test
  import Kollective.Factory

  setup %{conn: conn} do
    id = System.unique_integer([:positive])

    user =
      insert(:user,
        email: "district_user_#{id}@test.com",
        username: "district_user_#{id}",
        identity_hash: "hash_#{id}"
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "GET /api/districts/lookup" do
    test "returns district boundaries for a valid address", %{conn: conn} do
      stub(Kollective.External.CivicService, fn req_conn ->
        Req.Test.json(req_conn, %{
          "divisions" => %{
            "ocd-division/country:us/state:tx" => %{},
            "ocd-division/country:us/state:tx/cd:10" => %{},
            "ocd-division/country:us/state:tx/sldu:14" => %{},
            "ocd-division/country:us/state:tx/sldl:46" => %{}
          }
        })
      end)

      conn = get(conn, ~p"/api/districts/lookup", %{"address" => "1100 Congress Ave, Austin, TX"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "TX"
      assert data["federal_district"] == "10"
      assert data["state_senate_district"] == "14"
      assert data["state_district"] == "46"
    end

    test "returns 400 when address format is invalid", %{conn: conn} do
      stub(Kollective.External.CivicService, fn req_conn ->
        Plug.Conn.send_resp(req_conn, 400, "Bad Request")
      end)

      conn = get(conn, ~p"/api/districts/lookup", %{"address" => "Invalid Address Format"})

      assert %{"error" => "Invalid address format"} = json_response(conn, 400)
    end

    test "returns 400 when external service is unavailable", %{conn: conn} do
      stub(Kollective.External.CivicService, fn req_conn ->
        Plug.Conn.send_resp(req_conn, 500, "Internal Server Error")
      end)

      conn = get(conn, ~p"/api/districts/lookup", %{"address" => "100 Main St"})

      assert %{"error" => "Service unavailable"} = json_response(conn, 400)
    end
  end
end

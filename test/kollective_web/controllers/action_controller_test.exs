defmodule KollectiveWeb.ActionControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  describe "unauthenticated action endpoints" do
    test "GET /api/v1/actions returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/actions")
      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/actions returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/actions", %{})
      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "authenticated action endpoints" do
    setup :authenticate_user

    test "GET /api/v1/actions lists collective actions filtered by scope and category", %{
      conn: conn,
      user: user
    } do
      city = insert(:city)
      user = user |> Ecto.Changeset.change(%{city_id: city.id}) |> Kollective.Repo.update!()
      conn = assign(conn, :current_user, user)

      # Insert events with collective action categories
      event1 =
        insert(:event,
          user: user,
          category: "protest",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "March for climate change",
          start_time: DateTime.utc_now()
        )

      event2 =
        insert(:event,
          user: user,
          category: "rally",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "Local candidate rally",
          start_time: DateTime.utc_now()
        )

      # Standard informational event (should NOT be returned in list_collective_actions)
      _event3 =
        insert(:event,
          user: user,
          category: "standard",
          target_scope: :local,
          origin_city: city,
          origin_city_id: city.id,
          timezone: "UTC",
          event_status: "published",
          title: "Standard board meeting",
          start_time: DateTime.utc_now()
        )

      response =
        conn
        |> get(~p"/api/v1/actions", %{"category" => "protest", "scope" => "local"})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == to_string(event1.id)

      response_all =
        conn
        |> get(~p"/api/v1/actions", %{"category" => "all", "scope" => "local"})
        |> json_response(200)

      ids = Enum.map(response_all["data"], & &1["id"])
      assert to_string(event1.id) in ids
      assert to_string(event2.id) in ids
    end

    test "POST /api/v1/actions successfully launches a new grassroots action", %{
      conn: conn,
      user: _user
    } do
      params = %{
        "event" => %{
          "title" => "Rally for Civic Awareness",
          "description" => "Let us coordinate and raise awareness.",
          "category" => "protest",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "location_name" => "Main Plaza Town Hall Square",
          "street" => "789 Plaza St",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.to_iso8601()
        }
      }

      response =
        conn
        |> post(~p"/api/v1/actions", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["message"] =~ "Grassroots action successfully initiated"
      assert response["data"]["name"] == "Rally for Civic Awareness"
      assert response["data"]["category"] == "protest"
    end

    test "POST /api/v1/actions returns 422 if parameters are invalid", %{conn: conn} do
      params = %{
        "event" => %{
          "title" => ""
        }
      }

      response =
        conn
        |> post(~p"/api/v1/actions", params)
        |> json_response(422)

      assert Map.has_key?(response, "errors")
    end
  end
end

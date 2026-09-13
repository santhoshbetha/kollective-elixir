defmodule KollectiveWeb.CityControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  describe "GET /api/cities/search" do
    test "searches cities by prefix and country", %{conn: conn} do
      city1 =
        insert(:city,
          name: "Austin",
          state: "TX",
          country: "US",
          latitude: 30.2672,
          longitude: -97.7431
        )

      _city2 = insert(:city, name: "Dallas", state: "TX", country: "US")
      _city3 = insert(:city, name: "Auckland", country: "NZ")

      conn = get(conn, ~p"/api/cities/search", %{"q" => "Aus", "country" => "US"})

      assert response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) == 1

      item = hd(response["data"])
      assert item["id"] == city1.id
      assert item["name"] == "Austin, TX"
      assert item["lat"] == 30.2672
      assert item["lon"] == -97.7431
    end

    test "returns empty list when no matches found", %{conn: conn} do
      conn = get(conn, ~p"/api/cities/search", %{"q" => "Nonexistent", "country" => "US"})

      assert response = json_response(conn, 200)
      assert response["data"] == []
    end
  end
end

defmodule KollectiveWeb.BusinessSearchControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "GET /api/v1/businesses/search" do
    test "searches businesses by query term", %{conn: conn, user: user} do
      b1 = insert(:business, name: "Austin Artisan Bakery", user: user)
      _b2 = insert(:business, name: "Seattle Tech Hub", user: user)

      conn = get(conn, ~p"/api/v1/businesses/search", %{"q" => "Bakery"})
      assert %{"status" => "success", "count" => count, "data" => data} = json_response(conn, 200)

      assert count >= 1
      names = Enum.map(data, & &1["name"])
      assert b1.name in names
    end

    test "filters businesses by category", %{conn: conn, user: user} do
      b1 = insert(:business, category: "food_beverage", name: "Pizza Palace", user: user)

      conn = get(conn, ~p"/api/v1/businesses/search", %{"category" => "food_beverage"})
      assert %{"status" => "success", "data" => data} = json_response(conn, 200)

      names = Enum.map(data, & &1["name"])
      assert b1.name in names
    end
  end
end

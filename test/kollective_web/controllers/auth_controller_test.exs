defmodule KollectiveWeb.AuthControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  describe "GET /api/v1/auth/check-username" do
    test "returns available: true when username is not taken", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/check-username", %{"username" => "brand_new_user_123"})
      assert json_response(conn, 200)["available"] == true
      assert json_response(conn, 200)["status"] == "success"
    end

    test "returns available: false when username is taken", %{conn: conn} do
      insert(:user, username: "existing_user")

      conn = get(conn, ~p"/api/v1/auth/check-username", %{"username" => "existing_user"})
      assert json_response(conn, 200)["available"] == false
      assert json_response(conn, 200)["status"] == "success"
    end

    test "strips leading @ sign", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/check-username", %{"username" => "@cool_handle"})
      assert json_response(conn, 200)["username"] == "cool_handle"
      assert json_response(conn, 200)["available"] == true
    end

    test "returns 422 when username is too short", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/check-username", %{"username" => "a"})
      assert json_response(conn, 422)["code"] == "too_short"
    end

    test "returns 422 when username contains invalid characters", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/check-username", %{"username" => "invalid!user"})
      assert json_response(conn, 422)["code"] == "invalid_characters"
    end

    test "returns 400 when username param is missing", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/check-username")
      assert json_response(conn, 400)["error"] =~ "Missing username"
    end
  end
end

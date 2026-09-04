defmodule KollectiveWeb.NotificationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  describe "unauthenticated activity notification endpoints" do
    test "GET /api/v1/notifications returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/notifications")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "GET /api/v1/notifications/unread_count returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/notifications/unread_count")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/notifications/mark_as_read returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications/mark_as_read")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "authenticated activity notification endpoints" do
    setup :authenticate_user

    test "GET /api/v1/notifications lists chronological notifications", %{conn: conn, user: user} do
      # Insert notifications for the user
      n1 = insert(:notification, user: user, read: false)
      n2 = insert(:notification, user: user, read: true)

      response =
        conn
        |> get(~p"/api/v1/notifications")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])

      # Should return both notifications
      ids = Enum.map(response["data"], & &1["id"])
      assert to_string(n1.id) in ids
      assert to_string(n2.id) in ids
    end

    test "GET /api/v1/notifications cursor pagination works", %{conn: conn, user: user} do
      n1 = insert(:notification, user: user, read: false)
      n2 = insert(:notification, user: user, read: false)

      # List with limit 1
      response1 =
        conn
        |> get(~p"/api/v1/notifications", %{"limit" => "1"})
        |> json_response(200)

      assert length(response1["data"]) == 1
      # Keyset cursor pagination uses descending order (newest first)
      # So n2 (created last) should be returned first
      assert hd(response1["data"])["id"] == to_string(n2.id)
      assert response1["next_cursor"] == to_string(n2.id)

      # Fetch subsequent page using cursor
      response2 =
        conn
        |> get(~p"/api/v1/notifications", %{"limit" => "1", "cursor" => to_string(n2.id)})
        |> json_response(200)

      assert length(response2["data"]) == 1
      assert hd(response2["data"])["id"] == to_string(n1.id)
      assert response2["next_cursor"] == to_string(n1.id)
    end

    test "GET /api/v1/notifications/unread_count returns unread count", %{conn: conn, user: user} do
      # Insert read and unread notifications
      _n1 = insert(:notification, user: user, read: false)
      _n2 = insert(:notification, user: user, read: false)
      _n3 = insert(:notification, user: user, read: true)

      response =
        conn
        |> get(~p"/api/v1/notifications/unread_count")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["count"] == 2
    end

    test "POST /api/v1/notifications/mark_as_read marks all unread as read", %{
      conn: conn,
      user: user
    } do
      _n1 = insert(:notification, user: user, read: false)
      _n2 = insert(:notification, user: user, read: false)
      _n3 = insert(:notification, user: user, read: true)

      response =
        conn
        |> post("/api/v1/notifications/mark_as_read")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "2 notifications marked as read"

      # Verify count is now 0
      count_response =
        conn
        |> get("/api/v1/notifications/unread_count")
        |> json_response(200)

      assert count_response["count"] == 0
    end
  end
end

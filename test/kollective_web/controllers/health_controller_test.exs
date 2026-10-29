defmodule KollectiveWeb.HealthControllerTest do
  use KollectiveWeb.ConnCase

  test "GET /api/health", %{conn: conn} do
    conn = get(conn, "/api/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end

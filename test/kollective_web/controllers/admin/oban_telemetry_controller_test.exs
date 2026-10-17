defmodule KollectiveWeb.Admin.ObanTelemetryControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "GET /api/v1/admin/telemetry/oban" do
    test "returns Oban queue summary and recent failure metrics", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/telemetry/oban")
      assert %{"data" => data} = json_response(conn, 200)

      assert %{"summary" => summary, "recent_failures" => recent_failures} = data
      assert is_map(summary)
      assert is_list(recent_failures)
      assert Map.has_key?(summary, "completed")
      assert Map.has_key?(summary, "executing")
      assert Map.has_key?(summary, "retryable")
      assert Map.has_key?(summary, "discarded")
    end
  end
end

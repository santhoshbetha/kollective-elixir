defmodule KollectiveWeb.Admin.MeshRepairControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    # Register operator in Mnesia so SovereignAuth grants clearance
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")

    :mnesia.transaction(fn ->
      :mnesia.write(
        {:node_sovereign_operators, admin.username, "admin", "system", "2026-10-17T00:00:00Z"}
      )
    end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "MeshRepairController trigger_recovery" do
    test "returns 422 when target node is offline or refuses handshake", %{conn: conn} do
      payload = %{"node_name" => "offline_node@192.168.1.99"}

      conn = post(conn, ~p"/api/v1/admin/mesh/force_recovery", payload)
      assert response = json_response(conn, 422)
      assert response["error"] == "Target hardware node refused execution command handshakes."
    end

    test "rejects non-sovereign users with 403 Forbidden", %{conn: conn} do
      regular_user = insert(:user, is_admin: false, is_moderator: false, badge_type: "member")

      conn =
        conn
        |> assign(:current_user, regular_user)
        |> assign(:user, regular_user)

      payload = %{"node_name" => "some_node@127.0.0.1"}

      conn = post(conn, ~p"/api/v1/admin/mesh/force_recovery", payload)
      assert response = json_response(conn, 403)

      assert response["error"] =~ "Access Denied" or response["error"] =~ "Sovereign" or
               response["error"] =~ "Forbidden"
    end
  end
end

defmodule KollectiveWeb.Admin.NodeTopologyControllerTest do
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

  describe "GET /api/v1/admin/mesh/topology" do
    test "returns topology mesh metadata with local node", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/mesh/topology")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["cluster_size"] >= 1
      assert data["network_protocol"] == "Erlang_Distribution_PG2"
      assert is_list(data["nodes"])

      local_node = Enum.find(data["nodes"], & &1["is_local"])
      assert local_node != nil
      assert local_node["zone"] == "LOCAL_MASTER"
      assert local_node["status"] == "healthy_connected"
      assert local_node["node_name"] == Atom.to_string(Node.self())
    end
  end
end

defmodule KollectiveWeb.Admin.SovereignOperatorControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Moderation.SovereignOperator

  setup %{conn: conn} do
    # Clear Mnesia table
    if :node_sovereign_operators in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:node_sovereign_operators)
    end

    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "SovereignOperatorController lifecycle" do
    test "create dual-writes to Postgres and Mnesia", %{conn: conn} do
      payload = %{
        "operator" => %{
          "username" => "operator_alice",
          "role" => "admin"
        }
      }

      conn = post(conn, ~p"/api/v1/admin/sovereign_operators", payload)
      assert json_response(conn, 200)["status"] == "success"

      # Check Postgres
      assert Repo.get(SovereignOperator, "operator_alice") != nil

      # Check Mnesia
      assert {:atomic, [_rec]} =
               :mnesia.transaction(fn -> :mnesia.read(:node_sovereign_operators, "operator_alice") end)
    end

    test "index lists active sovereign operators", %{conn: conn} do
      # Seed in Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({:node_sovereign_operators, "op_bob", "moderator", "admin_root", "2026-10-17T00:00:00Z"})
      end)

      conn = get(conn, ~p"/api/v1/admin/sovereign_operators")
      assert %{"data" => operators} = json_response(conn, 200)

      usernames = Enum.map(operators, & &1["username"])
      assert "op_bob" in usernames
    end

    test "delete purges operator from Postgres and Mnesia", %{conn: conn, admin: admin} do
      # Insert in Postgres and Mnesia
      %SovereignOperator{}
      |> SovereignOperator.changeset(%{
        username: "op_charlie",
        role: "moderator",
        granted_by: admin.username
      })
      |> Repo.insert!()

      :mnesia.transaction(fn ->
        :mnesia.write({:node_sovereign_operators, "op_charlie", "moderator", admin.username, "2026-10-17T00:00:00Z"})
      end)

      conn = delete(conn, ~p"/api/v1/admin/sovereign_operators/op_charlie")
      assert json_response(conn, 200)["status"] == "success"

      assert Repo.get(SovereignOperator, "op_charlie") == nil

      assert {:atomic, []} =
               :mnesia.transaction(fn -> :mnesia.read(:node_sovereign_operators, "op_charlie") end)
    end

    test "delete returns 404 when operator not found on disk", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/admin/sovereign_operators/non_existent_op")
      assert json_response(conn, 404)["error"] == "Operator key mismatch on disk storage logs."
    end
  end
end

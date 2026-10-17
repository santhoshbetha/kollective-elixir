defmodule KollectiveWeb.Admin.SovereignAuditLogControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.AuditLog

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

  describe "GET /api/v1/admin/audit_logs" do
    test "lists recent audit logs", %{conn: conn, admin: admin} do
      # Insert audit log
      {:ok, log} =
        %AuditLog{}
        |> AuditLog.changeset(%{
          action: "dismiss",
          target_type: "Incident",
          target_id: "inc_123",
          actor_id: admin.id,
          metadata: %{"node_name" => "node_test@127.0.0.1"}
        })
        |> Repo.insert()

      conn = get(conn, ~p"/api/v1/admin/audit_logs")
      assert %{"data" => %{"logs" => logs, "node_name" => _node}} = json_response(conn, 200)

      log_ids = Enum.map(logs, & &1["id"])
      assert log.id in log_ids

      matching = Enum.find(logs, &(&1["id"] == log.id))
      assert matching["action"] == "dismiss"
      assert matching["actor_username"] == admin.username
      assert matching["target_identifier"] == "inc_123"
    end

    test "filters logs by action parameter", %{conn: conn, admin: admin} do
      {:ok, _log1} =
        %AuditLog{}
        |> AuditLog.changeset(%{
          action: "hard_ban",
          target_type: "User",
          target_id: "user_bad",
          actor_id: admin.id,
          metadata: %{}
        })
        |> Repo.insert()

      {:ok, _log2} =
        %AuditLog{}
        |> AuditLog.changeset(%{
          action: "grant_clearance",
          target_type: "User",
          target_id: "user_good",
          actor_id: admin.id,
          metadata: %{}
        })
        |> Repo.insert()

      conn = get(conn, ~p"/api/v1/admin/audit_logs?action=hard_ban")
      assert %{"data" => %{"logs" => logs}} = json_response(conn, 200)

      assert length(logs) >= 1
      assert Enum.all?(logs, &(&1["action"] == "hard_ban"))
    end
  end
end

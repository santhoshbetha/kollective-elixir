defmodule KollectiveWeb.Admin.StaffControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Accounts.AuditLogs

  setup %{conn: conn} do
    root_admin = insert(:user, is_admin: true, badge_type: "root")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, root_admin)
      |> assign(:user, root_admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, root_admin: root_admin}
  end

  describe "audit_logs/2" do
    test "fetches list of global audit logs for root dashboard", %{
      conn: conn,
      root_admin: root_admin
    } do
      {:ok, _log} =
        AuditLogs.create_audit_log(%{
          action: "SYSTEM_CONFIG_CHANGE",
          target_type: "System",
          target_id: "FLAG_1",
          actor_id: root_admin.id,
          metadata: %{"role" => "admin"}
        })

      conn = get(conn, ~p"/api/v1/admin/root/audit_logs")

      assert %{"data" => logs} = json_response(conn, 200)
      assert is_list(logs)
      assert length(logs) >= 1
    end
  end

  describe "promote_to_moderator/2" do
    test "promotes an existing user to moderator role", %{conn: conn} do
      target_user = insert(:user, is_moderator: false)

      conn =
        post(conn, ~p"/api/v1/admin/root/users/promote_to_moderator", %{
          "username" => target_user.username
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" =>
                 "Account @#{target_user.username} successfully promoted to Moderator. Access desk keys generated."
             }

      updated = Repo.get!(User, target_user.id)
      assert updated.is_moderator == true
    end

    test "returns 404 if targeted username is not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/admin/root/users/promote_to_moderator", %{
          "username" => "non_existent_user_9999"
        })

      assert json_response(conn, 404) == %{
               "error" => "Targeted username does not exist on platform registers."
             }
    end
  end

  describe "promote_to_admin/2" do
    test "elevates an existing user to administrator role", %{conn: conn} do
      target_user = insert(:user, is_admin: false)

      conn =
        post(conn, ~p"/api/v1/admin/root/users/promote_to_admin", %{
          "username" => target_user.username
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" =>
                 "Account @#{target_user.username} successfully elevated to Root Administrator status."
             }

      updated = Repo.get!(User, target_user.id)
      assert updated.is_admin == true
    end

    test "returns 404 if targeted username is not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/admin/root/users/promote_to_admin", %{
          "username" => "non_existent_user_8888"
        })

      assert json_response(conn, 404) == %{
               "error" => "Targeted username does not exist on platform registers."
             }
    end
  end

  describe "security clearance boundary" do
    test "blocks unauthorized non-root user", %{conn: conn} do
      regular_user = insert(:user, is_admin: false, badge_type: "user")

      conn =
        conn
        |> assign(:current_user, regular_user)
        |> assign(:user, regular_user)

      conn = get(conn, ~p"/api/v1/admin/root/audit_logs")

      assert json_response(conn, 403) == %{
               "error" => "Access denied: Unauthorized operator clearance level."
             }
    end
  end
end

defmodule KollectiveWeb.Admin.SecurityControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Ecto.Query
  import Kollective.Factory

  alias Kollective.Security.Security
  alias Kollective.Admins.Log

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:current_admin, admin)

    {:ok, conn: conn, admin: admin}
  end

  describe "index/2" do
    test "lists blacklisted IPs in RAM memory firewall", %{conn: conn} do
      Security.blacklist_ip("192.168.1.50")
      Security.blacklist_ip("10.0.0.25")

      conn = get(conn, ~p"/api/v1/admin/security/blacklist")

      assert %{
               "status" => "success",
               "data" => %{
                 "blacklisted_ips" => blacklisted_ips
               }
             } = json_response(conn, 200)

      assert "192.168.1.50" in blacklisted_ips
      assert "10.0.0.25" in blacklisted_ips

      # Cleanup
      Security.pardon_ip("192.168.1.50")
      Security.pardon_ip("10.0.0.25")
    end
  end

  describe "pardon/2" do
    test "pards a blacklisted IP address successfully and logs it", %{conn: conn, admin: admin} do
      Security.blacklist_ip("192.168.1.99")
      assert Security.ip_blacklisted?("192.168.1.99")

      conn = delete(conn, ~p"/api/v1/admin/security/blacklist/192.168.1.99")

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" =>
                 "IP address 192.168.1.99 has been pardoned and can now interact again."
             }

      refute Security.ip_blacklisted?("192.168.1.99")

      # Verify security audit log was written
      assert Kollective.Repo.exists?(
               from(l in Log,
                 where: l.user_id == ^admin.id and l.action == "ip_pardoned"
               )
             )
    end

    test "returns 404 error if IP is not blacklisted", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/admin/security/blacklist/10.9.9.9")

      assert json_response(conn, 404) == %{
               "status" => "error",
               "error" => "IP address not found inside active blacklist stores."
             }
    end
  end

  describe "lift_all/2" do
    test "flushes all IP blacklists and infraction strike markers", %{conn: conn, admin: admin} do
      Security.blacklist_ip("192.168.1.10")
      Security.blacklist_ip("192.168.1.20")
      assert Security.ip_blacklisted?("192.168.1.10")
      assert Security.ip_blacklisted?("192.168.1.20")

      conn = post(conn, ~p"/api/v1/admin/security/lift-cooldowns")

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" =>
                 "All user cooldown markers and IP memory blacklists have been flushed."
             }

      refute Security.ip_blacklisted?("192.168.1.10")
      refute Security.ip_blacklisted?("192.168.1.20")

      # Verify security audit log was written
      assert Kollective.Repo.exists?(
               from(l in Log,
                 where: l.user_id == ^admin.id and l.action == "bulk_cooldown_lift"
               )
             )
    end
  end

  describe "lockdown/2" do
    test "enables and disables platform-wide emergency lockdown successfully", %{
      conn: conn,
      admin: admin
    } do
      # 1. Enable lockdown
      conn_enable = post(conn, ~p"/api/v1/admin/security/lockdown/enable")

      assert json_response(conn_enable, 200) == %{
               "status" => "success",
               "message" =>
                 "Emergency Lockdown active! All new platform submissions are now routed to PENDING review."
             }

      assert Security.lockdown_active?()

      assert Kollective.Repo.exists?(
               from(l in Log,
                 where: l.user_id == ^admin.id and l.action == "emergency_lockdown_enabled"
               )
             )

      # 2. Disable lockdown
      conn_disable = post(conn, ~p"/api/v1/admin/security/lockdown/disable")

      assert json_response(conn_disable, 200) == %{
               "status" => "success",
               "message" => "Lockdown lifted. Standard moderation matrices resumed."
             }

      refute Security.lockdown_active?()

      assert Kollective.Repo.exists?(
               from(l in Log,
                 where: l.user_id == ^admin.id and l.action == "emergency_lockdown_disabled"
               )
             )
    end
  end

  describe "authorization boundaries" do
    test "denies access to non-administrative users", %{conn: conn} do
      # Replace connection assigns with a standard user profile
      non_admin = insert(:user, is_admin: false, is_moderator: false)

      conn =
        conn
        |> assign(:current_user, non_admin)
        |> assign(:current_admin, nil)

      # Call endpoints and assert they are blocked
      for {method, path} <- [
            {:get, "/api/v1/admin/security/blacklist"},
            {:delete, "/api/v1/admin/security/blacklist/1.1.1.1"},
            {:post, "/api/v1/admin/security/lift-cooldowns"},
            {:post, "/api/v1/admin/security/lockdown/enable"},
            {:post, "/api/v1/admin/security/lockdown/disable"}
          ] do
        conn_res = dispatch(conn, KollectiveWeb.Endpoint, method, path)

        assert %{
                 "status" => "error",
                 "code" => "unauthorized_access",
                 "message" =>
                   "You do not have the necessary administrative privileges to access this resource."
               } = json_response(conn_res, 403)
      end
    end
  end
end

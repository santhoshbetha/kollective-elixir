# lib/kollective_web/controllers/admin/security_controller.ex
defmodule KollectiveWeb.Admin.SecurityController do
  use KollectiveWeb, :controller

  alias Kollective.Security.Security
  alias Kollective.Repo
  alias Kollective.Admins.Log

  # ─── ACTION 1: LIST ACTIVE MEMORY IP BLACKLISTS ───
  # GET /api/v1/admin/security/blacklist
  def index(conn, _params) do
    # Reads direct-from-RAM Cachex clusters in under 0.001ms
    ips = Security.list_blacklisted_ips()
    json(conn, %{status: "success", data: %{blacklisted_ips: ips}})
  end

  # ─── ACTION 2: PARDON AN IP INFRACTION EARLY ───
  # DELETE /api/v1/admin/security/blacklist/:ip
  def pardon(conn, %{"ip" => ip}) do
    admin = conn.assigns.current_admin

    if Security.ip_blacklisted?(ip) do
      Security.pardon_ip(ip)
      # Log the manual override security pardon for audit transparency
      insert_security_audit_log(admin.id, "ip_pardoned", %{ip: ip})

      json(conn, %{
        status: "success",
        message: "IP address #{ip} has been pardoned and can now interact again."
      })
    else
      conn
      |> put_status(:not_found)
      |> json(%{status: "error", error: "IP address not found inside active blacklist stores."})
    end
  end

  # ─── ACTION 3: BULK LIFTS ALL COOLDOWNS ───
  # POST /api/v1/admin/security/lift-cooldowns
  def lift_all(conn, _params) do
    admin = conn.assigns.current_admin

    # Execute the atomic memory wipe across your Cachex layer
    Security.lift_all_cooldowns()

    # File the audit trail to account for the bulk change
    insert_security_audit_log(admin.id, "bulk_cooldown_lift", %{
      note: "Mistaken keyword setup corrected."
    })

    json(conn, %{
      status: "success",
      message: "All user cooldown markers and IP memory blacklists have been flushed."
    })
  end

  # ─── ACTION 4: ACTIVATE EMERGENCY EMERGENCY LOCKDOWN (KILL SWITCH) ───
  # POST /api/v1/admin/security/lockdown/enable
  def enable_lockdown(conn, _params) do
    admin = conn.assigns.current_admin

    # Activates the Cachex global flag. Forces ALL new post content parameters to "pending"
    Security.enable_lockdown()

    insert_security_audit_log(admin.id, "emergency_lockdown_enabled", %{
      reason: "Manual switch activated."
    })

    json(conn, %{
      status: "success",
      message:
        "Emergency Lockdown active! All new platform submissions are now routed to PENDING review."
    })
  end

  # ─── ACTION 5: DISABLE LOCKDOWN ───
  # POST /api/v1/admin/security/lockdown/disable
  def disable_lockdown(conn, _params) do
    admin = conn.assigns.current_admin

    Security.disable_lockdown()

    insert_security_audit_log(admin.id, "emergency_lockdown_disabled", %{
      reason: "Resuming standard operation rules."
    })

    json(conn, %{
      status: "success",
      message: "Lockdown lifted. Standard moderation matrices resumed."
    })
  end

  # --- Private Governance Logger Component  ---
  defp insert_security_audit_log(admin_id, action, metadata) do
    %Log{
      action: action,
      # Global security events don't target single resource models
      target_id: nil,
      target_type: "System",
      user_id: admin_id,
      metadata: metadata
    }
    |> Repo.insert!()
  end
end

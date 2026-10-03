defmodule KollectiveWeb.Admin.SecurityController do
  use KollectiveWeb, :controller

  alias Kollective.Security.Security
  alias Kollective.Repo
  alias Kollective.Admins.Log
  alias Kollective.Accounts.AuditLogs

  # 🛡️ PRIVILEGE PROTECTION PLUG: Guard security endpoints against standard audience profiles
  plug :verify_security_clearance

  @doc """
  GET /api/v1/admin/security/blacklist
  Reads direct-from-RAM Cachex clusters in under 0.001ms.
  """
  def index(conn, _params) do
    ips = Security.list_blacklisted_ips()
    json(conn, %{status: "success", data: %{blacklisted_ips: ips}})
  end

  @doc """
  DELETE /api/v1/admin/security/blacklist/:ip
  Pardons an active firewall IP infraction early.
  """
  def pardon(conn, %{"ip" => ip}) do
    # ✅ FIX 1: Align session maps with your unified current_user system identifier token
    admin = conn.assigns[:current_user] || conn.assigns[:user]

    if Security.ip_blacklisted?(ip) do
      Security.pardon_ip(ip)

      # 1. File legacy admin tracking row safely
      insert_security_audit_log(admin.id, "ip_pardoned", %{ip: ip})

      # 2. 🚀 NEW REAL-TIME LEDGER GOVERNANCE SYNC:
      # Pushes instant update elements over WebSockets straight to your Admin dashboard lists!
      AuditLogs.create_audit_log(%{
        action: "FIREWALL_IP_PARDON",
        target_type: "System",
        target_id: ip,
        actor_id: admin.id,
        metadata: %{"ip" => ip, "role" => "admin"}
      })

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

  @doc """
  POST /api/v1/admin/security/lift-cooldowns
  Flushes all user throttling markers and memory blacklists across Cachex layers.
  """
  def lift_all(conn, _params) do
    admin = conn.assigns[:current_user] || conn.assigns[:user]

    Security.lift_all_cooldowns()

    insert_security_audit_log(admin.id, "bulk_cooldown_lift", %{
      note: "Mistaken keyword setup corrected."
    })

    # NEW REAL-TIME LEDGER GOVERNANCE SYNC
    AuditLogs.create_audit_log(%{
      action: "FIREWALL_FLUSH_ALL",
      target_type: "System",
      target_id: "ALL_COOLDOWNS",
      actor_id: admin.id,
      metadata: %{"note" => "Bulk cooldown wipe triggered.", "role" => "admin"}
    })

    json(conn, %{
      status: "success",
      message: "All user cooldown markers and IP memory blacklists have been flushed."
    })
  end

  @doc """
  POST /api/v1/admin/security/lockdown/enable
  Activates the Cachex global flag, routing ALL new platform submissions to pending review.
  """
  def enable_lockdown(conn, _params) do
    admin = conn.assigns[:current_user] || conn.assigns[:user]

    Security.enable_lockdown()

    insert_security_audit_log(admin.id, "emergency_lockdown_enabled", %{
      reason: "Manual switch activated."
    })

    # 🚀 NEW REAL-TIME LEDGER GOVERNANCE SYNC:
    # Triggers immediate dashboard color alerts across active staff sockets!
    AuditLogs.create_audit_log(%{
      action: "EMERGENCY_LOCKDOWN_ON",
      target_type: "System",
      target_id: "PLATFORM_SHIELD",
      actor_id: admin.id,
      metadata: %{"reason" => "Manual kill switch activated.", "role" => "admin"}
    })

    json(conn, %{
      status: "success",
      message:
        "Emergency Lockdown active! All new platform submissions are now routed to PENDING review."
    })
  end

  @doc """
  POST /api/v1/admin/security/lockdown/disable
  Lifts the emergency lockdown state and resumes standard moderation metrics matrices.
  """
  def disable_lockdown(conn, _params) do
    admin = conn.assigns[:current_user] || conn.assigns[:user]

    Security.disable_lockdown()

    insert_security_audit_log(admin.id, "emergency_lockdown_disabled", %{
      reason: "Resuming standard operation rules."
    })

    # 🚀 NEW REAL-TIME LEDGER GOVERNANCE SYNC
    AuditLogs.create_audit_log(%{
      action: "EMERGENCY_LOCKDOWN_OFF",
      target_type: "System",
      target_id: "PLATFORM_SHIELD",
      actor_id: admin.id,
      metadata: %{"reason" => "Resuming standard operational matrices.", "role" => "admin"}
    })

    json(conn, %{
      status: "success",
      message: "Lockdown lifted. Standard moderation matrices resumed."
    })
  end

  # --- Private Security Logger Component ---
  defp insert_security_audit_log(admin_id, action, metadata) do
    %Log{
      action: action,
      target_id: nil,
      target_type: "System",
      user_id: admin_id,
      metadata: metadata
    }
    |> Repo.insert!()
  end

  defp verify_security_clearance(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    if user &&
         (user.is_admin || user.is_moderator || Map.get(user, :badge_type) in ["admin", "root"]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied: Unauthorized security operator clearance level."})
      |> halt()
    end
  end
end

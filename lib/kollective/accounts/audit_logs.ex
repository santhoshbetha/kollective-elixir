defmodule Kollective.Accounts.AuditLogs do
  @moduledoc """
  🔒 CENTRALIZED PLATFORM GOVERNANCE AUDIT ENGINE
  Manages database insertions and real-time WebSocket broadcasts for both
  private Organization actions and global Root Admin/Moderator operations desks.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.AuditLog

  @doc """
  Creates an audit log entry in the database and automatically handles
  real-time PubSub broadcasts to the relevant administrative channels.
  """
  def create_audit_log(attrs \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, audit_log} ->
        # Preload the actor profile cleanly in one pass to supply names to the frontend layout
        audit_log = Repo.preload(audit_log, :actor)
        broadcast_audit_event(audit_log)
        {:ok, audit_log}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Fetches a high-security global audit log trail for Root Admin and Moderator desks.
  Ensures the database query preloads actor references to protect against N+1 query traps.
  """
  def list_global_audit_logs(params \\ %{}) do
    limit = Map.get(params, "limit", 50)

    AuditLog
    # Global system logs either have no organization or target system-wide indicators
    |> order_by([a], desc: a.id)
    |> limit(^limit)
    |> preload([:actor])
    |> Repo.all()
  end

  # ─── PRIVATE TRANSMISSION ROUTERS ───

  # Case A: Private Organization Action (Scoped to an active business account handle)
  defp broadcast_audit_event(%AuditLog{organization_id: org_id} = log) when not is_nil(org_id) do
    payload = format_payload(log)

    # 1. Stream down the private WebSocket channel to corporate supervisors
    KollectiveWeb.Endpoint.broadcast(
      "org_admin_audit:#{org_id}",
      "new_audit_log",
      payload
    )

    # 2. Duplicate to the global platform ledger if the action was taken by an app-wide Admin
    if is_nil(log.metadata["is_global_action"]) == false do
      KollectiveWeb.Endpoint.broadcast("admin_notifications:global", "new_global_log", payload)
    end
  end

  # Case B: System Governance Action (Global Root Admin or Moderator Alert)
  defp broadcast_audit_event(%AuditLog{} = log) do
    payload = format_payload(log)
    KollectiveWeb.Endpoint.broadcast("admin_notifications:global", "new_global_log", payload)
  end

  defp format_payload(log) do
    %{
      id: log.id,
      action: log.action,
      target_type: log.target_type,
      target_id: log.target_id,
      inserted_at: log.inserted_at,
      metadata: log.metadata,
      operator_name: (log.actor && log.actor.username) || "system"
    }
  end
end

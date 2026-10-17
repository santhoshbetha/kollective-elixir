defmodule KollectiveWeb.Admin.StaffController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.AuditLogs
  alias KollectiveWeb.ChangesetJSON

  # 🛡️ PRIVILEGE DEFENSE PLUG: Restricts endpoints strictly to logged-in root staff accounts
  plug(:verify_root_clearance)

  @doc """
  GET /api/v1/admin/root/audit_logs
  Hydrates the System Ledger sidebar component inside the RootAdminDashboard.
  """
  def audit_logs(conn, params) do
    logs = AuditLogs.list_global_audit_logs(params)

    serialized_logs =
      Enum.map(logs, fn log ->
        %{
          id: log.id,
          action: log.action,
          target_type: log.target_type,
          target_id: log.target_id,
          inserted_at: log.inserted_at,
          role: Map.get(log.metadata || %{}, "role", "user"),
          operator_name: (log.actor && log.actor.username) || "system"
        }
      end)

    json(conn, %{data: serialized_logs})
  end

  @doc """
  POST /api/v1/admin/root/users/promote_to_moderator
  Promotes an active user account to the Moderator staff tier.
  """
  def promote_to_moderator(conn, %{"username" => username}) do
    admin = conn.assigns.current_user || conn.assigns[:user]

    case Accounts.update_staff_role(username, :moderator, admin.id) do
      {:ok, user} ->
        # 🚀 REAL-TIME AUDIT INTEGRATION:
        # Logs the promotion to the database and streams it over WebSockets instantly [INDEX].
        AuditLogs.create_audit_log(%{
          action: "PROMOTE_TO_MODERATOR",
          target_type: "User",
          target_id: "@#{user.username}",
          actor_id: admin.id,
          metadata: %{"role" => "moderator"}
        })

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message:
            "Account @#{user.username} successfully promoted to Moderator. Access desk keys generated."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Targeted username does not exist on platform registers."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        # Unified layout error handling matching your exact ChangesetJSON structure
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  @doc """
  POST /api/v1/admin/root/users/promote_to_admin
  Promotes an active user account to the absolute Root Admin staff tier.
  """
  def promote_to_admin(conn, %{"username" => username}) do
    admin = conn.assigns.current_user || conn.assigns[:user]

    case Accounts.update_staff_role(username, :admin, admin.id) do
      {:ok, user} ->
        # 🚀 REAL-TIME AUDIT INTEGRATION:
        AuditLogs.create_audit_log(%{
          action: "PROMOTE_TO_ADMIN",
          target_type: "User",
          target_id: "@#{user.username}",
          actor_id: admin.id,
          metadata: %{"role" => "admin"}
        })

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Account @#{user.username} successfully elevated to Root Administrator status."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Targeted username does not exist on platform registers."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # --- Private Security Plug Interceptors ---

  defp verify_root_clearance(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    if user && (user.is_admin || Map.get(user, :badge_type) in ["admin", "root", "staff"]) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Access denied: Unauthorized operator clearance level."})
      |> halt()
    end
  end
end

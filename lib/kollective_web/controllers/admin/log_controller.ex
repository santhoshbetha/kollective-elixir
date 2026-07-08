# lib/kollective_web/controllers/admin/log_controller.ex
defmodule KollectiveWeb.Admin.LogController do
  use KollectiveWeb, :controller
  alias Kollective.Admins.Governance

  # GET /api/v1/admin/audit_logs
  def index(conn, params) do
    # Protected by your router's require_admin_authenticated plugs
    filters = Map.get(params, "filters", %{})
    logs = Governance.list_audit_logs(filters, params)

    json(conn, %{
      status: "success",
      data:
        Enum.map(logs, fn log ->
          %{
            id: to_string(log.id),
            action: log.action,
            target_id: to_string(log.target_id),
            target_type: log.target_type,
            metadata: log.metadata,
            inserted_at: Calendar.strftime(log.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
            admin: %{
              id: to_string(log.admin.id),
              username: log.admin.username,
              role: if(log.admin.is_admin, do: "admin", else: "moderator")
            }
          }
        end)
    })
  end
end

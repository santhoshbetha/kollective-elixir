defmodule KollectiveWeb.AuditLogController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.AuditLogJSON

  @doc """
  Lists audit logs for the current organization context with pagination.
  """
  # GET /api/v1/org-settings/audit_logs
  def index(conn, params) do
    org_id = conn.assigns[:current_org_id] || params["org_id"]

    limit = parse_int(Map.get(params, "limit", 50), 50)
    offset = parse_int(Map.get(params, "offset", 0), 0)

    audit_logs = Accounts.list_audit_logs(org_id, limit: limit, offset: offset)

    conn
    |> put_status(:ok)
    |> json(AuditLogJSON.index(audit_logs))
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_int(_val, default), do: default
end

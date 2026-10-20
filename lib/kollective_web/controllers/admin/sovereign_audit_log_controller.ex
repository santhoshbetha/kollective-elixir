defmodule KollectiveWeb.Admin.SovereignAuditLogController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.AuditLog

  @doc """
  GET /api/v1/admin/audit_logs
  Pulls the recent cryptographic operational trail logged by sovereign administrators.
  """
  def index(conn, params) do
    limit =
      case params["limit"] do
        nil ->
          30

        l when is_integer(l) ->
          l

        l when is_binary(l) ->
          case Integer.parse(l) do
            {int, _} -> int
            _ -> 30
          end
      end

    action_filter = Map.get(params, "action")

    base_query =
      from(log in AuditLog,
        left_join: u in assoc(log, :actor),
        select: %{
          id: log.id,
          actor_username: coalesce(u.username, "system"),
          action: log.action,
          target_identifier: coalesce(log.target_id, ""),
          node_name:
            fragment("COALESCE(?->>'node_name', ?)", log.metadata, ^Atom.to_string(Node.self())),
          inserted_at: log.inserted_at
        },
        order_by: [desc: log.inserted_at]
      )

    query =
      if action_filter && action_filter != "" do
        from(log in base_query, where: log.action == ^action_filter)
      else
        base_query
      end

    logs =
      query
      |> limit(^limit)
      |> Repo.all()

    json(conn, %{
      data: %{
        logs: logs,
        node_name: Atom.to_string(Node.self())
      }
    })
  end
end

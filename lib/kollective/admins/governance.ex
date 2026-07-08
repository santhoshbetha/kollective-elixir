# lib/kollective/admins/governance.ex
defmodule Kollective.Admins.Governance do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Admins.Log

  @doc """
  Fetches a paginated, filter-supported feed stream of system audit logs.
  Preloads the executing administrator profile for accountability tracking.
  """
  def list_audit_logs(filters \\ %{}, params \\ %{}) do
    limit = Map.get(params, "limit", 50)
    offset = Map.get(params, "offset", 0)

    Log
    |> filter_by_action(filters["action"])
    |> filter_by_admin(filters["user_id"])
    |> preload([:admin])
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  # --- Dynamic Query Filter Clause Blocks ---
  def apply_query(query), do: query

  defp filter_by_action(query, nil), do: query
  defp filter_by_action(query, ""), do: query
  defp filter_by_action(query, action_str), do: from(l in query, where: l.action == ^action_str)

  defp filter_by_admin(query, nil), do: query
  defp filter_by_admin(query, admin_id), do: from(l in query, where: l.user_id == ^admin_id)
end

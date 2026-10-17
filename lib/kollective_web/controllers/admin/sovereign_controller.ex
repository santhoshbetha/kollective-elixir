defmodule KollectiveWeb.Admin.SovereignController do
  @moduledoc """
  DEPRECATED: Kept for reference. Not wired to router.ex.

  Replacements:
  - Incident adjudication (`resolve/2`) has moved to `KollectiveWeb.Admin.MeshIncidentController.resolve/2`
    via `POST /api/v1/admin/incidents/:id/resolve`.
  - Operator clearance management (`index_operators/2`, `grant_access/2`, `revoke_access/2`) has moved to
    `KollectiveWeb.Admin.SovereignOperatorController` (`GET/POST/DELETE /api/v1/admin/sovereign_operators`),
    which implements hybrid dual-writes (PostgreSQL + Mnesia) and integrates with the frontend
    `SovereignPermissionsPanel.jsx`.
  """
  use KollectiveWeb, :controller

  # Inject the local sovereignty plugs we designed previously to guard these routes [1]
  plug KollectiveWeb.Plugs.SovereignAuth when action in [:grant_access, :revoke_access]

  alias Kollective.Database.MnesiaSovereignContext
  alias Kollective.Database.MnesiaResolutionEngine

  # POST /api/v1/admin/incidents/:id/resolve
  def resolve(conn, %{"id" => id, "action" => action_type}) do
    operator = conn.assigns[:current_user] || conn.assigns[:user]

    case MnesiaResolutionEngine.resolve_incident(id, action_type, operator.id) do
      {:ok, status} ->
        json(conn, %{status: "success", final_status: status})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Incident file expired."})

      _ ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Transaction crash."})
    end
  end

  # GET /api/v1/admin/sovereign/operators
  def index_operators(conn, _params) do
    json(conn, %{data: MnesiaSovereignContext.list_local_operators()})
  end

  # POST /api/v1/admin/sovereign/operators/grant
  def grant_access(conn, %{"username" => username, "role" => role}) do
    operator = conn.assigns[:current_user] || conn.assigns[:user]

    case MnesiaSovereignContext.grant_node_clearance(username, role, operator.username) do
      {:ok, data} ->
        json(conn, %{status: "success", data: data})

      _ ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Failed to write node keys."})
    end
  end

  # DELETE /api/v1/admin/sovereign/operators/revoke/:username
  def revoke_access(conn, %{"username" => username}) do
    :ok = MnesiaSovereignContext.revoke_node_clearance(username)
    json(conn, %{status: "success", message: "Node permissions keys terminated successfully."})
  end
end

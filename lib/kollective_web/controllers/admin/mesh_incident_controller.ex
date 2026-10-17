defmodule KollectiveWeb.Admin.MeshIncidentController do
  use KollectiveWeb, :controller
  require Logger

  alias Kollective.Database.MnesiaResolutionEngine
  alias Kollective.Database.MnesiaQueueEngine

  @doc """
  POST /api/v1/admin/incidents/lease_next
  Attempts to lease the next available incident from Mnesia cluster memory.
  """
  def lease_next(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    moderator_id = user.id

    country_code =
      params["country_code"] || Map.get(user, :country) || Map.get(user, :country_code) || "US"

    is_global? =
      case params["is_global"] do
        true ->
          true

        "true" ->
          true

        false ->
          false

        "false" ->
          false

        _ ->
          user.is_admin || user.role == :admin ||
            Map.get(user, :badge_type) in ["admin", "root", "staff"]
      end

    case MnesiaQueueEngine.lease_next_incident(moderator_id, country_code, is_global?) do
      {:ok, ticket} ->
        json(conn, %{data: ticket})

      {:error, :empty_queue} ->
        conn
        |> put_status(:ok)
        |> json(%{data: nil, status: "empty_queue", message: "No available incidents in queue."})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to lease next incident from queue engine."})
    end
  end

  @doc """
  POST /api/v1/admin/incidents/:id/claim
  Attempts to lock and claim a moderation ticket within Mnesia cluster memory and Postgres.
  """
  def claim(conn, %{"id" => incident_id}) do
    # Safely extract your authenticated user's ID
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    case MnesiaResolutionEngine.claim_incident(incident_id, current_user.id) do
      {:ok, :claimed} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Incident lock acquired successfully."})

      {:error, :incident_already_locked} ->
        conn
        |> put_status(:conflict)
        |> json(%{status: "error", error: "Incident is already leased by another operator."})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Target incident record not found."})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", error: "Internal cluster transaction failure."})
    end
  end

  @doc """
  POST /api/v1/admin/incidents/:id/release
  Voluntarily drops a ticket lock, returning it back to the global pool.
  """
  def release(conn, %{"id" => incident_id}) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    case MnesiaResolutionEngine.release_incident_lease(incident_id, current_user.id) do
      {:ok, :released} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Incident lock released successfully."})

      {:error, :unauthorized_lease_holder} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", error: "You cannot drop a lease held by another operator."})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Target incident record not found."})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", error: "Failed to release distributed cluster record lock."})
    end
  end

  @doc """
  POST /api/v1/admin/incidents/:id/extend
  Pings the system to attach an extra 5 minutes onto an active incident lease.
  """
  def extend(conn, %{"id" => incident_id}) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    case MnesiaResolutionEngine.extend_incident_lease(incident_id, current_user.id) do
      {:ok, :extended} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Lease rolled forward smoothly."})

      {:error, :lease_ownership_lost} ->
        conn
        |> put_status(:precondition_failed)
        |> json(%{
          status: "error",
          error: "Extension rejected. Your lease window expired or was reassigned."
        })

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", error: "Internal transactional pipeline failure."})
    end
  end

  @doc """
  POST /api/v1/admin/incidents/:id/resolve
  Adjudicates an incident (dismiss, soft_delete, hard_ban) atomically across Mnesia and Postgres,
  or delegates scholar restore/ban requests to ScholarIncidentController.
  """
  def resolve(conn, %{"id" => incident_id, "action" => action_type} = params) do
    if action_type in ["restore", "ban"] do
      KollectiveWeb.Admin.ScholarIncidentController.resolve(conn, params)
    else
      current_user = conn.assigns[:current_user] || conn.assigns[:user]

      case MnesiaResolutionEngine.resolve_incident(incident_id, action_type, current_user.id) do
        {:ok, status} ->
          json(conn, %{status: "success", final_status: status})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{status: "error", error: "Target incident record not found or expired."})

        {:error, _reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{status: "error", error: "Internal transactional resolution failure."})
      end
    end
  end
end

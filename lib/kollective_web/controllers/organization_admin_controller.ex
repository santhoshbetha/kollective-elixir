defmodule KollectiveWeb.OrganizationAdminController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]

  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  # GET /api/v1/organizations/:org_id/pending_members
  def pending_members(conn, %{"org_id" => org_id}) do
    manager = conn.assigns.current_user

    # 1. Enforce strict membership permission guards
    is_admin? =
      Repo.exists?(
        from(m in OrganizationMembership,
          where:
            m.organization_id == ^org_id and m.user_id == ^manager.id and m.role == :admin and
              m.status == :approved
        )
      )

    if not is_admin? do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "unauthorized",
        message: "You are not an administrator for this organization."
      })
    else
      # 2. Extract database rows matching pending states in exactly one pass
      pending_list =
        Repo.all(
          from(m in OrganizationMembership,
            where: m.organization_id == ^org_id and m.status == :pending,
            # Preloads profile structures to eliminate N+1 loop overhead
            preload: [:user],
            order_by: [desc: m.id]
          )
        )

      json(conn, %{
        status: "success",
        data:
          Enum.map(pending_list, fn m ->
            %{
              membership_id: to_string(m.id),
              role: m.role,
              inserted_at: Calendar.strftime(m.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
              user: %{
                id: to_string(m.user.id),
                username: m.user.username,
                avatar_url: m.user.avatar_url
              }
            }
          end)
      })
    end
  end

  # POST /api/v1/organization_requests/:membership_id/process
  # Expected params payload: %{"status" => "approved"} or "rejected"
  def update_status(conn, %{"membership_id" => id, "status" => status_str})
      when status_str in ["approved", "rejected"] do
    manager = conn.assigns.current_user
    action_atom = String.to_existing_atom(status_str)

    # Invokes our transaction-safe multi-tier approval logic block
    case Accounts.process_join_request(manager, id, action_atom) do
      {:ok, _changes} ->
        json(conn, %{status: "success", message: "Membership request successfully processed."})

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "unauthorized"})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "operation_failed"})
    end
  end

  def update_status(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid parameter payload."})
end

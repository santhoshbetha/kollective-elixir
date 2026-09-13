defmodule KollectiveWeb.OrganizationAdminController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]

  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership
  alias KollectiveWeb.OrganizationAdminJSON

  # GET /api/v1/organizations/:org_id/requests
  def pending_members(conn, %{"org_id" => org_id}) do
    manager =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    is_admin? =
      manager != nil and
        Repo.exists?(
          from(m in OrganizationMembership,
            where:
              m.organization_id == ^org_id and m.user_id == ^manager.id and
                m.role in [:admin, :owner] and m.status == :approved
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
      pending_list =
        Repo.all(
          from(m in OrganizationMembership,
            where: m.organization_id == ^org_id and m.status == :pending,
            preload: [:user],
            order_by: [desc: m.id]
          )
        )

      conn
      |> put_status(:ok)
      |> json(OrganizationAdminJSON.pending_members(pending_list))
    end
  end

  # POST /api/v1/organizations/:org_id/members/:user_id/role
  def change_role(conn, %{"org_id" => org_id, "user_id" => user_id, "new_role" => new_role_str})
      when new_role_str in ["owner", "admin", "contributor"] do
    manager =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    new_role = String.to_existing_atom(new_role_str)

    can_edit? =
      manager != nil and
        Repo.exists?(
          from(m in OrganizationMembership,
            where:
              m.organization_id == ^org_id and m.user_id == ^manager.id and
                m.role in [:owner, :admin] and m.status == :approved
          )
        )

    target_membership = Accounts.get_organization_membership_by_user(user_id, org_id)

    cond do
      not can_edit? ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "unauthorized", message: "Only Owners or Admins can modify roles."})

      is_nil(target_membership) ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "member_not_found"})

      target_membership.role == :owner and new_role != :owner and
          Accounts.count_organization_owners(org_id) <= 1 ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "validation_error", message: "Cannot remove the last Owner."})

      true ->
        case Accounts.update_organization_membership(target_membership, %{role: new_role}) do
          {:ok, _changes} ->
            conn
            |> put_status(:ok)
            |> json(OrganizationAdminJSON.action_success("Role updated successfully."))

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "update_failed", message: "Failed to update role."})
        end
    end
  end

  def change_role(conn, _),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid parameter payload."})

  # POST /api/v1/organization_requests/:membership_id/process
  def update_status(conn, %{"membership_id" => id, "status" => status_str})
      when status_str in ["approved", "rejected"] do
    manager =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    action_atom = String.to_existing_atom(status_str)

    case Accounts.process_join_request(manager, id, action_atom) do
      {:ok, _changes} ->
        conn
        |> put_status(:ok)
        |> json(
          OrganizationAdminJSON.action_success("Membership request successfully processed.")
        )

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "unauthorized"})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "operation_failed"})
    end
  end

  def update_status(conn, _),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid parameter payload."})
end

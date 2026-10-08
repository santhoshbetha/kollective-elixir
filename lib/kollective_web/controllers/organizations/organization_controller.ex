defmodule KollectiveWeb.OrganizationController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.OrganizationJSON

  # GET /api/v1/organizations/search
  # Expected params: ?q=news
  def search(conn, params) do
    query_str = params["q"] || params["query"] || ""

    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    organizations = Accounts.search_organizations_by_type(query_str)

    conn
    |> put_status(:ok)
    |> json(OrganizationJSON.search(organizations, current_user))
  end

  # POST /api/v1/organizations/:org_id/join
  def join_request(conn, params) do
    org_id = params["org_id"] || params["id"]

    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    if is_nil(org_id) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Organization ID is required."})
    else
      case Accounts.request_organization_join(user.id, org_id) do
        {:ok, _membership} ->
          conn
          |> put_status(:ok)
          |> json(OrganizationJSON.join_request_success())

        {:error, :invalid_target_account} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Target account is not an organization entity."})

        {:error, _changeset} ->
          conn
          |> put_status(:conflict)
          |> json(%{
            error: "duplicate_request",
            message: "You have already requested to join this organization."
          })
      end
    end
  end

  # POST /api/v1/org-admin/organizations/:org_id/invite
  def invite_contributor(conn, %{"email" => email, "role" => role} = params) do
    org_id = conn.assigns[:current_org_id] || params["org_id"]

    with {:ok, membership} <- Accounts.create_invite(org_id, email, role) do
      membership = Repo.preload(membership, :user)

      conn
      |> put_status(:ok)
      |> json(OrganizationJSON.invite_success("Invitation sent successfully.", membership, email))
    else
      {:error, :user_already_invited} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", message: "User is already invited."})

      {:error, :user_already_member} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", message: "User is already a member."})

      {:error, :invalid_role} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", message: "Invalid role."})

      {:error, :organization_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "validation_error", message: "Organization not found."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "validation_error",
          message: "You are not authorized to perform this action."
        })

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "validation_error",
          message: "No account found with email address: #{email}"
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_error",
          message: changeset.message
        })
    end
  end

  # POST /api/v1/org-admin/organizations/:org_id/invites/:invite_id/resend
  def resend_invite(conn, %{"org_id" => org_id, "invite_id" => invite_id}) do
    with {:ok, membership} <- Accounts.resend_invite(org_id, invite_id) do
      membership = Repo.preload(membership, :user)

      conn
      |> put_status(:ok)
      |> json(
        OrganizationJSON.invite_success(
          "Invitation resent successfully.",
          membership,
          membership.user.email
        )
      )
    else
      {:error, :invalid_invite} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "validation_error", message: "Invite not found."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "validation_error",
          message: "You are not authorized to perform this action."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_error",
          message: changeset.message
        })
    end
  end

  # DELETE /api/v1/org-admin/organizations/:org_id/invite/:invite_id
  def remove_invite(conn, %{"org_id" => org_id, "invite_id" => invite_id}) do
    with {:ok, membership} <- Accounts.remove_invite(org_id, invite_id) do
      membership = Repo.preload(membership, :user)

      conn
      |> put_status(:ok)
      |> json(
        OrganizationJSON.invite_success(
          "Invitation removed successfully.",
          membership,
          membership.user.email
        )
      )
    else
      {:error, :invalid_invite} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "validation_error", message: "Invite not found."})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "validation_error",
          message: "You are not authorized to perform this action."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_error",
          message: changeset.message
        })
    end
  end

  # POST /api/v1/org-admin/transfer-ownership
  # Handling Owner Retirement / Transfer
  # If the current owner is retiring, they can transfer ownership to another member.
  # The new owner must be an existing member of the organization.
  # The current owner will be demoted to a Admin.
  # Target user will be promoted to Owner
  def transfer_ownership(conn, params) do
    org_id = conn.assigns[:current_org_id] || params["org_id"]

    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    new_owner_id = params["new_owner_id"]

    if current_user && Accounts.is_owner?(org_id, current_user.id) do
      case Accounts.transfer_ownership(org_id, current_user.id, new_owner_id) do
        {:ok, _} ->
          conn
          |> put_status(:ok)
          |> json(OrganizationJSON.ownership_transferred())

        {:error, _step, _error, _changes} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{status: "error", message: "Failed to transfer ownership"})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        status: "error",
        error: "Absolute ownership credentials required to execute this operation.",
        message: "Absolute ownership credentials required to execute this operation."
      })
    end
  end

  # PUT /api/v1/org-settings/profile
  def update_profile(conn, params) do
    org_id = conn.assigns[:current_org_id] || params["org_id"]
    org_role = conn.assigns[:org_role]

    cond do
      is_nil(org_id) ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          error: "Organization context is required.",
          message: "Organization context is required."
        })

      org_role not in [:owner, :admin] ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          error: "Only organization administrators can update organization settings.",
          message: "Only organization administrators can update organization settings."
        })

      true ->
        case Accounts.get_user(org_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{
              status: "error",
              error: "Organization not found.",
              message: "Organization not found."
            })

          org ->
            case Accounts.update_user_profile(org, params) do
              {:ok, updated_org} ->
                conn
                |> put_status(:ok)
                |> json(OrganizationJSON.update_profile_success(updated_org))

              {:error, changeset} ->
                errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{
                  status: "error",
                  error: "validation_error",
                  message: "Failed to update organization profile.",
                  errors: errors
                })
            end
        end
    end
  end
end

# lib/kollective_web/controllers/organization_controller.ex
defmodule KollectiveWeb.OrganizationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  # GET /api/v1/organizations/search
  # Expected params: ?q=news
  def search(conn, %{"q" => query_str}) do
    current_user = conn.assigns.current_user

    # 1. Fetch matching user accounts filtered by type: :organization
    organizations = Accounts.search_organizations_by_type(query_str)

    conn
    |> put_status(:ok)
    # 2. Phoenix 1.7 standard: Serialize uniformly using AccountJSON
    |> json(%{
      status: "success",
      data: KollectiveWeb.AccountJSON.index(%{users: organizations, for: current_user})
    })
  end

  # POST /api/v1/organizations/:org_id/join_request
  def join_request(conn, %{"org_id" => org_id}) do
    user = conn.assigns.current_user

    # Invokes our unified context join-request module
    case Accounts.request_organization_join(user.id, org_id) do
      {:ok, _membership} ->
        json(conn, %{
          status: "success",
          message: "Request successfully sent to organization administrators."
        })

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

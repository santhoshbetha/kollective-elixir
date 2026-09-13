defmodule KollectiveWeb.Plugs.AssignOrganization do
  import Plug.Conn
  import Phoenix.Controller
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  def init(opts), do: opts

  def call(conn, _opts) do
    # Assumes your token authentication plug ran before this
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    header_org_id =
      case get_req_header(conn, "x-organization-id") do
        [id] when id != "" -> id
        _ -> nil
      end

    org_id = header_org_id || conn.path_params["org_id"] || conn.params["org_id"]

    cond do
      is_nil(org_id) ->
        # No header or param found, user is operating out of their personal profile
        assign(conn, :current_org_id, nil)

      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "You must log in to access this resource."})
        |> halt()

      true ->
        # Verify the user actually has access to this organization context
        case Accounts.get_organization_membership_by_user(user.id, org_id) do
          %OrganizationMembership{role: role, status: status}
          when status in [:approved, :active] ->
            conn
            |> assign(:current_org_id, org_id)
            |> assign(:org_role, role)

          _ ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "You are not a member of this organization."})
            |> halt()
        end
    end
  end
end

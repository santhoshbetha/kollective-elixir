defmodule KollectiveWeb.Plugs.AssignOrganization do
  import Plug.Conn
  import Phoenix.Controller
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  alias Kollective.Accounts.Organizations

  def init(opts), do: opts

  def call(conn, _opts) do
    # Assumes your token authentication plug ran before this
    user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    explicit_header_id =
      case get_req_header(conn, "x-organization-id") do
        [id] when id != "" -> id
        _ -> nil
      end

    route_org_id = conn.path_params["org_id"] || conn.params["org_id"]

    context_header_id =
      case get_req_header(conn, "x-workspace-context-id") do
        [id] when id != "" -> id
        _ ->
          case get_req_header(conn, "x-active-account-id") do
            [id] when id not in ["", "personal", "usr-1"] ->
              if user && to_string(user.id) == to_string(id), do: nil, else: id
            _ -> nil
          end
      end

    target_org_id = explicit_header_id || route_org_id || context_header_id

    cond do
      # 1. APIAuth already assigned an active organization context and no conflicting explicit org requested
      is_nil(target_org_id) and not is_nil(conn.assigns[:current_organization]) ->
        org = conn.assigns[:current_organization]
        role = conn.assigns[:org_role] || :member

        conn
        |> assign(:current_org_id, to_string(org.id))
        |> assign(:org_role, role)

      # 2. No target org specified and APIAuth is in personal mode
      is_nil(target_org_id) ->
        conn
        |> assign(:current_org_id, nil)
        |> assign(:org_role, nil)

      # 3. Target org requested, but user is unauthenticated
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "You must log in to access this resource."})
        |> halt()

      # 4. Target matches already resolved current_organization
      not is_nil(conn.assigns[:current_organization]) and
          to_string(conn.assigns[:current_organization].id) == to_string(target_org_id) ->
        org = conn.assigns[:current_organization]
        role = conn.assigns[:org_role] || :member

        conn
        |> assign(:current_org_id, to_string(org.id))
        |> assign(:org_role, role)

      # 5. Target org requested and needs verification
      true ->
        case Accounts.get_active_membership(user.id, target_org_id) do
          %OrganizationMembership{organization: org, role: role} when not is_nil(org) ->
            permissions = Organizations.permissions_for_role(role)

            conn
            |> assign(:current_organization, org)
            |> assign(:current_org_id, to_string(org.id))
            |> assign(:org_role, role)
            |> assign(:active_account_id, to_string(org.id))
            |> assign(:account_type, org.type)
            |> assign(:permissions, permissions)

          _ ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "You are not a member of this organization."})
            |> halt()
        end
    end
  end
end

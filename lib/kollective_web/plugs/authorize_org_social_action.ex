defmodule KollectiveWeb.Plugs.AuthorizeOrgSocialAction do
  @moduledoc """
  Authorizes social mutation actions (follows, likes, reblogs, poll votes, and event RSVPs).
  - Personal accounts: allowed.
  - Organization accounts: permitted ONLY if the active user's role in the organization
    evaluates to an Administrator or Owner (:admin or :owner).
  - All non-admin requests attempting to perform organization actions are immediately
    rejected with an HTTP 403 Forbidden JSON API response, halting connection execution.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Kollective.Accounts.{Accounts, OrganizationMembership}

  def init(opts), do: opts

  def call(conn, opts) do
    if is_organization_actor?(conn) do
      role = resolve_org_role(conn)

      if role in [:admin, :owner, "admin", "owner"] do
        conn
      else
        message =
          Keyword.get(
            opts,
            :message,
            "Only administrators can perform social actions on behalf of this organization."
          )

        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "forbidden",
          message: message
        })
        |> halt()
      end
    else
      conn
    end
  end

  def is_organization_actor?(conn) do
    conn.assigns[:account_type] == :organization or
      conn.assigns[:current_organization] != nil or
      (conn.assigns[:current_org_id] != nil and conn.assigns[:current_org_id] != "")
  end

  defp resolve_org_role(conn) do
    case conn.assigns[:org_role] do
      nil ->
        org_id =
          conn.assigns[:current_org_id] ||
            (conn.assigns[:current_organization] && conn.assigns[:current_organization].id)

        user = conn.assigns[:current_user]

        if org_id && user do
          case Accounts.get_active_membership(user.id, org_id) do
            %OrganizationMembership{role: role} -> role
            _ -> nil
          end
        end

      role ->
        role
    end
  end
end

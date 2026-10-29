defmodule KollectiveWeb.Plugs.RequireOrgAdmin do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if is_organization_actor?(conn) do
      role = resolve_org_role(conn)

      if role in [:admin, :owner, "admin", "owner", :lead_organizer, "lead_organizer"] do
        conn
      else
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          error: "forbidden",
          message: "Only administrators can perform actions on behalf of this organization."
        })
        |> halt()
      end
    else
      conn
    end
  end

  def is_organization_actor?(conn) do
    conn.assigns[:account_type] in [:organization, "organization"] or
      conn.assigns[:current_organization] != nil or
      (conn.assigns[:current_org_id] != nil and conn.assigns[:current_org_id] not in ["", "personal", "usr-1"])
  end

  defp resolve_org_role(conn) do
    cond do
      conn.assigns[:org_role] ->
        conn.assigns[:org_role]

      conn.assigns[:current_organization] && conn.assigns[:current_user] ->
        case Kollective.Accounts.Accounts.get_active_membership(
               conn.assigns[:current_user].id,
               conn.assigns[:current_organization].id
             ) do
          %{role: role} -> role
          _ -> nil
        end

      conn.assigns[:current_org_id] && conn.assigns[:current_user] ->
        case Kollective.Accounts.Accounts.get_active_membership(
               conn.assigns[:current_user].id,
               conn.assigns[:current_org_id]
             ) do
          %{role: role} -> role
          _ -> nil
        end

      true ->
        nil
    end
  end
end

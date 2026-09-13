# lib/kollective_web/channels/org_admin_audit_channel.ex
defmodule KollectiveWeb.OrgAdminAuditChannel do
  use KollectiveWeb, :channel

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership

  # Allows the admin client to connect to "org_admin_audit:SOME_ORG_ID"
  def join("org_admin_audit:" <> org_id, _payload, socket) do
    user_id = socket.assigns[:user_id]

    cond do
      is_nil(user_id) ->
        {:error, %{reason: "unauthenticated"}}

      user_id == org_id ->
        {:ok, assign(socket, :org_id, org_id)}

      true ->
        case Accounts.get_organization_membership_by_user(user_id, org_id) do
          %OrganizationMembership{role: role, status: status}
          when role in [:admin, :owner] and status in [:approved, :active] ->
            {:ok, assign(socket, :org_id, org_id)}

          _ ->
            {:error, %{reason: "unauthorized"}}
        end
    end
  end

  # This intercept handles the backend broadcast!/3 event
  # It intercepts "new_audit_log" and pushes it down the WebSocket to the browser
  def handle_out("new_audit_log", payload, socket) do
    push(socket, "new_audit_log", payload)
    {:noreply, socket}
  end
end

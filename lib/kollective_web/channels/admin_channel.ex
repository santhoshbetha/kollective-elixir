defmodule KollectiveWeb.AdminChannel do
  use KollectiveWeb, :channel
  alias Kollective.Accounts.AuditLogs

  @doc """
  High-security entry gate for app-wide administrators and platform moderators.
  """
  def join("admin_notifications:global", _payload, socket) do
    # GUEST PROTECTION SHIELD: Enforce strict role permissions checks
    user = socket.assigns[:user]

    if socket.assigns[:is_authenticated] && user &&
         user.badge_type in ["admin", "root", "moderator", "staff"] do
      # Optional: Send down the immediate history timeline array to hydrate dashboards instantly
      initial_history = AuditLogs.list_global_audit_logs(%{limit: 30})

      {:ok, %{history: initial_history}, socket}
    else
      {:error, %{reason: "unauthorized_platform_clearance_tier"}}
    end
  end

  # Stream the global system action alerts across the websocket frame instantly
  def handle_out("new_global_log", payload, socket) do
    push(socket, "new_global_log", payload)
    {:noreply, socket}
  end
end

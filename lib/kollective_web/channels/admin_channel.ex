defmodule KollectiveWeb.AdminChannel do
  use KollectiveWeb, :channel
  alias Kollective.Accounts.AuditLogs
  alias KollectiveWeb.Presence

  intercept(["new_global_log"])

  @doc """
  High-security entry gate for app-wide administrators and platform moderators.
  Handles decentralized multi-node geofencing routing via Erlang Process Groups.
  """
  def join("admin_notifications:global", _payload, socket) do
    # GUEST PROTECTION SHIELD: Enforce strict role permissions checks
    user = socket.assigns[:user] || socket.assigns[:current_user]

    if socket.assigns[:is_authenticated] && user &&
         user.badge_type in ["admin", "root", "moderator", "staff"] do
      # 🚀 1. GEOGRAPHIC PROCESS REGISTRATION MATRIX
      # Dynamically maps this live socket process into the correct distributed cluster lane
      cond do
        user.badge_type in ["admin", "root"] or
            Map.get(user.metadata || %{}, "global_mod") == true ->
          # Global staff monitor and catch alerts across all international boundaries
          :ok = :pg.join(Kollective.PubSub, :mods_global, self())

        is_binary(user.country_code) and
            Regex.match?(~r/^[A-Za-z]{2,3}$/, String.trim(user.country_code)) ->
          # Regional moderators link cleanly to localized country pools (e.g. :mods_zone_IN)
          clean_cc = user.country_code |> String.trim() |> String.upcase()
          region_topic = String.to_atom("mods_zone_#{clean_cc}")
          :ok = :pg.join(Kollective.PubSub, region_topic, self())

        true ->
          # Fallback bucket if country metadata mapping tags are transiently absent
          :ok = :pg.join(Kollective.PubSub, :mods_zone_fallback, self())
      end

      # 🚀 THE PRESENCE FIX: Intercept the socket process and track it locally.
      # This handles tracking multi-node connections seamlessly.
      send(self(), :after_join_presence_sync)

      # ⚡ 2. HISTORICAL SIDEBAR HYDRATION
      # Send down the immediate history timeline array to hydrate dashboards instantly
      initial_history = AuditLogs.list_global_audit_logs(%{limit: 30})

      {:ok, %{history: initial_history}, socket}
    else
      {:error, %{reason: "unauthorized_platform_clearance_tier"}}
    end
  end

  @doc """
  Asynchronously executes presence tracking handshakes once channel mounts complete.
  """
  def handle_info(:after_join_presence_sync, socket) do
    user = socket.assigns[:user] || socket.assigns[:current_user]

    {:ok, _} =
      Presence.track(socket, "mod:#{user.id}", %{
        username: user.username,
        badge_type: user.badge_type,
        country_code: String.upcase(user.country_code || "GLOBAL"),
        # Dynamic regional footprint tracking
        node_host: Atom.to_string(Node.self()),
        online_at: System.system_time(:second)
      })

    # Broadcast initial state snapshot down to the newly mounted browser connection
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Stream the global system action alerts across the websocket frame instantly
  def handle_out("new_global_log", payload, socket) do
    push(socket, "new_global_log", payload)
    {:noreply, socket}
  end
end

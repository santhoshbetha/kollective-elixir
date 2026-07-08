defmodule KollectiveWeb.UserChannel do
  use KollectiveWeb, :channel
  alias KollectiveWeb.Presence

  @impl true
  def join("user_notifications:" <> user_id, _payload, socket) do
    # SECURITY GUARD: Guarantee users can only subscribe to their own rooms
    if to_string(socket.assigns.user_id) == user_id do
      # Async side-effect task: Registers the online marker immediately
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id

    # 1. Register user metrics securely into Cachex or the Phoenix Presence tracker
    {:ok, _} =
      Presence.track(socket, "user:#{user_id}", %{
        online_at: System.system_time(:second)
      })

    # 2. Push the global active room count out to the React frontend client
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end

defmodule KollectiveWeb.NotificationChannel do
  use KollectiveWeb, :channel

  # 1. AUTHENTICATED JOIN HANDSHAKE
  @impl true
  def join("user_notifications:" <> user_id, _payload, socket) do
    # SECURITY GUARD: Guarantee users can only subscribe to their own alert streams
    if to_string(socket.assigns.user_id) == user_id do
      # Subscribe this explicit socket process to the app-wide internal PubSub.
      # This allows other context modules (like Likes or Follows) to send alerts here.
      Phoenix.PubSub.subscribe(Kollective.PubSub, "user_notifications:#{user_id}")

      # Perform an async post-join fetch task (e.g., getting the current database count)
      send(self(), :after_join)

      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # 2. FETCH INITIAL METRICS ASYNC
  @impl true
  def handle_info(:after_join, socket) do
    _user_id = socket.assigns.user_id

    # Optional: Fetch current unread badge metrics using your business context logic
    # initial_count = Kollective.Notifications.get_unread_count(user_id)
    initial_count = 0

    # Push the current snapshot to the newly connected React frontend
    push(socket, "initial_state", %{unread_count: initial_count})

    {:noreply, socket}
  end

  # 3. INTERCEPT INTERNAL SYSTEM PUBSUB BROADCASTS
  # :new_notification is the internal message name inside your Elixir backend server processes.
  # "new_notification" is the external event name sent across the network over WebSockets. Your React client must match this string exactly
  # to hear the incoming like updates.
  @impl true
  # Catches the message format passed from other internal Elixir modules
  def handle_info({:new_notification, notification_payload}, socket) do
    # Stream the raw notification payload safely over the WebSocket to React
    push(socket, "new_notification", notification_payload)

    {:noreply, socket}
  end

  # BACKWARD COMPATIBILITY MATCHERS
  # Catches raw text toast dispatches originating from Endpoint.broadcast calls
  @impl true
  def handle_out("new_notification", payload, socket) do
    push(socket, "new_notification", payload)
    {:noreply, socket}
  end
end

defmodule KollectiveWeb.EventChatChannel do
  use KollectiveWeb, :channel
  # alias KollectiveWeb.Presence

  @impl true
  def join("event_chat:" <> event_id, _payload, socket) do
    # Assign the event_id to the socket state so you can track it if needed
    {:ok, assign(socket, :event_id, event_id)}
  end

  # Incoming chat messages from React can be handled here if needed
  @impl true
  def handle_in("new_message", %{"body" => body}, socket) do
    # Broadcast to everyone else in this specific chat room instance
    broadcast!(socket, "new_message", %{
      body: body,
      user_id: socket.assigns.user_id,
      inserted_at: DateTime.utc_now()
    })

    {:reply, :ok, socket}
  end

  # @impl true
  # def handle_info(:after_join, socket) do
  #  user_id_string = to_string(socket.assigns.user_id)

  #  # 1. Start tracking this specific user inside this unique room instance.
  #  # Default 'is_typing' to false on connection initialization.
  #  {:ok, _} =
  #    Presence.track(socket, user_id_string, %{
  #      username: socket.assigns[:username] || "Anonymous",
  #      is_typing: false,
  #      online_at: System.system_time(:second)
  #    })

  #  # 2. Push the current room list snapshot down to the newly connected user
  #  push(socket, "presence_state", Presence.list(socket))
  #  {:noreply, socket}
  # end

  # @impl true
  # 3. LISTEN FOR LIVE TYPING TOGGLES FROM THE FRONTEND
  # def handle_in("typing", %{"is_typing" => is_typing}, socket) do
  #  user_id_string = to_string(socket.assigns.user_id)

  #  # Update this socket's presence metadata atomically in RAM.
  #  # Phoenix Presence will automatically broadcast a "presence_diff" out
  #  # to everyone else in the room to signal the change.
  #  {:ok, _} =
  #    Presence.update(socket, user_id_string, fn existing_meta ->
  #      Map.put(existing_meta, :is_typing, is_typing)
  #    end)

  #  {:reply, :ok, socket}
  # end
end

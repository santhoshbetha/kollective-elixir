#  "Unread Badges"
# 2. Updating last_read_at (Phoenix Channels)
# When a user opens a chat room in React, you must "mark as read" by updating their timestamp.
# You can do this automatically when they join the channel.

# Flow:
# 1. React: Calls socket.channel("conversation:123").
# 2. Elixir (join): Validates user, saves 123 to socket.assigns, and triggers :after_join.
# 3. Elixir (handle_info): Grabs 123 from socket.assigns and updates the database.

defmodule KollectiveWeb.ConversationChannel do
  use Phoenix.Channel
  alias KollectiveWeb.Presence

  def join("conversation:" <> conversation_id, _params, socket) do
    # 1. Store the ID in assigns for later use
    socket = assign(socket, :conversation_id, conversation_id)

    # 2. Check if the user is actually a participant before letting them in
    if Kollective.Chats.Chats.is_participant?(conversation_id, socket.assigns.user_id) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # you trigger this automatically when the user joins the conversation's Phoenix Channel.
  def handle_info1(:after_join, socket) do
    # 3. Now we use the assigned ID from the socket
    Kollective.Chats.Chats.mark_as_read(socket.assigns.conversation_id, socket.assigns.user_id)

    # Optional: Broadcast to the OTHER user that their message was read
    # KollectiveWeb.Endpoint.broadcast("user:#{other_user_id}", "messages_read", %{
    #  conversation_id: socket.assigns.conversation_id
    # })

    {:noreply, socket}
  end

  # "Read Receipts" (blue checkmarks)
  # Real-time Blue Ticks (Phoenix Channels)
  # When User B joins the channel (which triggers your mark_as_read function), you must broadcast a
  # "Read Update" so User A’s ticks turn blue immediately.
  # lib/kollective_web/channels/conversation_channel.ex
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id
    conv_id = socket.assigns.conversation_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. Mark as read in DB
    Kollective.Chats.Chats.mark_as_read(conv_id, user_id)

    # 2. Broadcast to the OTHER person in the room
    broadcast_from(socket, "partner_read", %{
      last_read_at: now,
      user_id: user_id
    })

    {:noreply, socket}
  end

  # Delivery Receipts:
  # lib/kollective_web/channels/conversation_channel.ex
  def handle_in("message_delivered", _payload, socket) do
    user_id = socket.assigns.user_id
    conv_id = socket.assigns.conversation_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. Update the 'last_delivered_at' for the RECIPIENT
    Kollective.Chats.Chats.mark_as_delivered(conv_id, user_id)

    # 2. Notify the SENDER so their gray tick turns into two ticks
    broadcast_from(socket, "partner_delivered", %{
      last_delivered_at: now,
      user_id: user_id
    })

    {:noreply, socket}
  end

  # Typing Indicators
  def handle_in("typing", %{"is_typing" => true}, socket) do
    # Track the user with 'typing' status in the conversation's presence
    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        typing: true,
        # Helpful for the React UI
        username: socket.assigns.username
      })

    {:noreply, socket}
  end

  def handle_in("typing", %{"is_typing" => false}, socket) do
    # Stop tracking the typing status
    Presence.untrack(socket, socket.assigns.user_id)
    {:noreply, socket}
  end

  # "Decryption Failures"
  # Handling the Rekey Request (Elixir Backend)
  # The server acts as a relay. It passes the "Rekey Request" back to the sender's active session.
  def handle_in("request_rekey", payload, socket) do
    # Broadcast to the SENDER of the original message
    # This tells their React app: "Hey, User B couldn't read that. Please re-send."
    broadcast_from(socket, "incoming_rekey_request", payload)
    {:noreply, socket}
  end
end

defmodule KollectiveWeb.ConversationChannel do
  import Ecto.Query

  use KollectiveWeb, :channel
  require Logger

  alias Kollective.Chats.Chats
  alias Kollective.Repo
  alias Kollective.Chats.Participant

  @impl true
  def join("conversation:" <> conversation_id, _payload, socket) do
    user_id = socket.assigns.user_id

    # 🟢 ALIGNED: Uses your exact is_participant?/2 context guard function
    if Chats.is_participant?(conversation_id, user_id) do
      {:ok, assign(socket, :conversation_id, conversation_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # ==========================================
  # 🟢 CLAUSE 1: Real-Time Read Receipts (Fixed Match Clause)
  # ==========================================
  @impl true
  def handle_in("read_receipt", _payload, socket) do
    conversation_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    # ✅ SAFE MATCH: Captures any number of rows (0, 1, or 50) without crashing the socket process!
    {_count, _} = Chats.mark_as_read(conversation_id, user_id)

    # Broadcast read confirmation back out over the room WebSocket to your partner
    broadcast!(socket, "message_read", %{
      conversation_id: conversation_id,
      reader_id: user_id,
      read_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    {:reply, :ok, socket}
  end

  # ==========================================
  # ⚡ CLAUSE 2: Real-Time Delivery Receipts (Double Checkmarks)
  # ==========================================
  @impl true
  def handle_in("mark_delivered", payload, socket) do
    conversation_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id
    msg_ids = Map.get(payload, "message_ids") || List.wrap(Map.get(payload, "message_id", []))
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # ⚡ Update the caller participant's last_delivered_at timestamp
    Chats.mark_as_delivered(conversation_id, user_id)

    # Broadcast delivery confirmations down the channel loop so senders can render gray check icons
    broadcast!(socket, "delivery_receipt_bump", %{
      user_id: to_string(user_id),
      conversation_id: to_string(conversation_id),
      message_ids: msg_ids,
      delivered_at: DateTime.to_iso8601(now)
    })

    {:reply, :ok, socket}
  end

  # ==========================================
  # 💬 CLAUSE 3: Typing Status Heartbeat
  # ==========================================
  @impl true
  def handle_in("typing_heartbeat", payload, socket) do
    user_id = socket.assigns.user_id
    status = Map.get(payload, "is_typing", false)
    username = (socket.assigns[:user] && socket.assigns[:user].username) || "Someone"

    broadcast_from!(socket, "typing_receipt_broadcast", %{
      user_id: to_string(user_id),
      username: username,
      is_typing: status
    })

    {:noreply, socket}
  end

  # ==========================================
  # 📣 CLAUSE 4: Direct Message Core Ingress (Fully Aligned)
  # ==========================================
  # Captures incoming WebSocket messages, commits them to the database transaction,
  # and broadcasts them to BOTH the active window AND the recipient's background notification line!
  @impl true
  def handle_in("send_direct_message", params, socket) do
    sender_id = socket.assigns.user_id
    conv_id = socket.assigns.conversation_id
    client_nonce = Map.get(params, "nonce")
    text_payload = Map.get(params, "text") || Map.get(params, "content", "")

    msg_params = %{
      "encrypted_content" => text_payload,
      "text" => text_payload
    }

    case Chats.create_message_with_attachment(sender_id, conv_id, msg_params) do
      {:ok, %{message: message}} ->
        room_payload = KollectiveWeb.MessageJSON.broadcast_data(message)

        room_payload =
          if client_nonce, do: Map.put(room_payload, :nonce, client_nonce), else: room_payload

        broadcast!(socket, "new_message", room_payload)
        trigger_background_drawer_popup(sender_id, conv_id)

        {:reply, {:ok, %{status: "success", message_id: message.id}}, socket}

      {:error, _failed_step, _changeset, _} ->
        {:reply, {:error, %{reason: "database_transaction_failed"}}, socket}
    end
  end

  # ==========================================
  # 🗑️ CLAUSE 5: Real-Time Message Deletion
  # ==========================================
  @impl true
  def handle_in("delete_message", %{"message_id" => msg_id}, socket) do
    user_id = socket.assigns.user_id
    conversation_id = socket.assigns.conversation_id

    case Chats.get_message(msg_id) do
      nil ->
        {:reply, {:error, %{reason: "message_not_found"}}, socket}

      message ->
        if to_string(message.sender_id) == to_string(user_id) do
          case Chats.soft_delete_message(message) do
            {:ok, updated_msg} ->
              broadcast!(socket, "message_deleted", %{
                "message_id" => to_string(updated_msg.id),
                "conversation_id" => to_string(conversation_id),
                "deleted_text" => "🚫 This message was deleted by the sender."
              })

              {:reply, {:ok, %{status: "success"}}, socket}

            {:error, _changeset} ->
              {:reply, {:error, %{reason: "database_mutation_failed"}}, socket}
          end
        else
          {:reply, {:error, %{reason: "unauthorized_ownership_tier"}}, socket}
        end
    end
  end

  # ==========================================
  # 🛡️ FALLBACK: Catch unhandled events to prevent GenServer process crashes
  # ==========================================
  @impl true
  def handle_in(event, payload, socket) do
    Logger.debug(
      "Unhandled event in ConversationChannel: #{inspect(event)} with payload: #{inspect(payload)}"
    )

    {:noreply, socket}
  end

  # --- Private Real-Time Background Notification Triggers ---
  defp trigger_background_drawer_popup(sender_id, conversation_id) do
    sender = Repo.get(Kollective.Accounts.User, sender_id)

    recipient_id =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.one()

    if recipient_id && sender do
      unread_count = Chats.get_unread_count(conversation_id, recipient_id)

      alert_payload = %{
        "id" => Ecto.UUID.generate(),
        "type" => "dm_badge_update",
        "conversation_id" => to_string(conversation_id),
        "unread_count" => unread_count,
        "sender_id" => to_string(sender_id),
        "sender_username" => sender.username,
        "operator_name" => sender.username,
        "preview_text" => "Sent you an encrypted direct message."
      }

      KollectiveWeb.Endpoint.broadcast!(
        "user_notifications:#{recipient_id}",
        "new_notification",
        alert_payload
      )
    end
  end
end

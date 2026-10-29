defmodule KollectiveWeb.ChatGroupChannel do
  use KollectiveWeb, :channel
  require Logger
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Chats.Chats
  alias Kollective.Chats.Message
  alias KollectiveWeb.MessageJSON

  @doc """
  SECURE GROUP handshakes entry gate.
  Verifies member clearance before mounting the live WebSocket synchronization loop.
  """
  @impl true
  def join("chat_group:" <> group_id, _payload, socket) do
    user_id = socket.assigns.user_id

    # Enforce participant verification checks against your Conversation database schema records
    if Chats.is_participant?(group_id, user_id) do
      # 🚀 PERFORMANCE HYDRATION: Fetch the last 30 messages inside the join payload
      # to hydrate the group screen immediately without waiting for a separate REST API query.
      history =
        from(m in Message,
          where: m.conversation_id == ^group_id,
          order_by: [desc: m.id],
          limit: 30
        )
        |> Repo.all()
        |> Enum.reverse()

      # Return structural data array token to client context components
      {:ok, %{messages: MessageJSON.index(history)}, assign(socket, :group_id, group_id)}
    else
      {:error, %{reason: "unauthorized_group_clearance_tier"}}
    end
  end

  # ==========================================
  # 📢 CLAUSE 1: Processing Incoming Text/Media Comments
  # ==========================================
  @impl true
  def handle_in("new_group_comment", %{"text" => text_payload} = params, socket) do
    sender_id = socket.assigns.user_id
    group_id = socket.assigns.group_id
    client_nonce = Map.get(params, "nonce")

    msg_params = %{
      "encrypted_content" => text_payload,
      "text" => text_payload
    }

    case Chats.create_message_with_attachment(sender_id, group_id, msg_params) do
      {:ok, %{message: message}} ->
        # Broadcast the serialized message down the channel to every active participant window
        payload = MessageJSON.broadcast_data(message)
        payload = if client_nonce, do: Map.put(payload, :nonce, client_nonce), else: payload

        broadcast!(socket, "new_message", payload)
        {:reply, {:ok, %{message_id: message.id}}, socket}

      {:error, _failed_step, _changeset, _} ->
        {:reply, {:error, %{reason: "group_transaction_failed"}}, socket}
    end
  end

  # ==========================================
  # ⚡ CLAUSE 2: Processing Double-Gray Tick Delivery Receipts
  # Updates the double-gray tick delivery trackers when a user hydrates their chat feed.
  # ==========================================
  @impl true
  def handle_in("mark_delivered", %{"message_ids" => msg_ids}, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # ⚡ ACCELERATED ATOMIC SQL OPERATION:
    # Update the caller user's last_delivered_at timestamp entry index instantly
    from(p in Kollective.Chats.Participant,
      where: p.conversation_id == ^group_id and p.user_id == ^user_id
    )
    |> Repo.update_all(set: [last_delivered_at: now])

    # Broadcast delivery confirmations down the channel loop so senders can render gray check icons
    broadcast!(socket, "delivery_receipt_bump", %{
      user_id: to_string(user_id),
      message_ids: msg_ids,
      delivered_at: DateTime.to_iso8601(now)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("typing_heartbeat", %{"is_typing" => status}, socket) do
    user_id = socket.assigns.user_id
    username = socket.assigns[:username] || "Someone"

    # Broadcast a transient signal to everyone else in the room
    broadcast_from!(socket, "typing_receipt_broadcast", %{
      user_id: to_string(user_id),
      username: username,
      is_typing: status
    })

    {:noreply, socket}
  end



  # ==========================================
  # 🗑️ CLAUSE 3 REFACTORED: Real-Time Message Deletion with Moderator Override
  # ==========================================
  @impl true
  def handle_in("delete_message", %{"message_id" => msg_id}, socket) do
    user_id = socket.assigns.user_id
    group_id = socket.assigns.group_id

    # Extract staff credentials injected into the channel socket parameters by your join plugs
    user_badge = socket.assigns[:user_badge] || "citizen"
    is_operator? = user_badge in ["admin", "root", "moderator", "staff"]

    case Kollective.Chats.Chats.get_message(msg_id) do
      nil ->
        {:reply, {:error, %{reason: "message_not_found"}}, socket}

      message ->
        # 🛡️ SOVEREIGN ENFORCEMENT VALIDATION LAYER OVERRIDE:
        # Access is granted if the user is the original creator, OR if they are a verified staff moderator!
        if to_string(message.sender_id) == to_string(user_id) or is_operator? do
          case Kollective.Chats.Chats.soft_delete_message(message) do
            {:ok, updated_msg} ->
              # Format custom text indicators if an action was forced by a moderator
              eviction_notice_text =
                if to_string(message.sender_id) == to_string(user_id) do
                  "🚫 This message was deleted by the sender."
                else
                  "🛡️ This content block was redacted by local node moderation staff."
                end

              broadcast!(socket, "message_deleted", %{
                "message_id" => to_string(updated_msg.id),
                "conversation_id" => to_string(group_id),
                "deleted_text" => eviction_notice_text
              })

              # Log enforcement choices directly to your permanent Sovereign Audit tables
              if is_operator? do
                # Kollective.Accounts.AuditLogs.log_action(%{
                #  action: "message_redaction",
                #  actor_username: socket.assigns.username,
                #  target_identifier: to_string(updated_msg.id),
                #  node_name: Atom.to_string(Node.self())
                # })
                _ =
                  Kollective.Accounts.AuditLogs.create_audit_log(%{
                    actor_id: user_id,
                    action: "MESSAGE_REDACTION",
                    target_type: "Message",
                    target_id: to_string(updated_msg.id),
                    metadata: %{
                      "note" => "Message deleted by operator.",
                      "conversation_id" => to_string(group_id),
                      "role" => user_badge,
                      "node_name" => Atom.to_string(Node.self()),
                      "actor_username" => socket.assigns.username
                    }
                  })
              end

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
    Logger.debug("Unhandled event in ChatGroupChannel: #{inspect(event)} with payload: #{inspect(payload)}")
    {:noreply, socket}
  end
end

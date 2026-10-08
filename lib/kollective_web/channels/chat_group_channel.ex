defmodule KollectiveWeb.ChatGroupChannel do
  use KollectiveWeb, :channel
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Chats.Chats
  alias Kollective.Chats.Message
  alias KollectiveWeb.MessageJSON

  @doc """
  🔒 SECURE GROUP handshakes entry gate.
  Verifies member clearance before mounting the live WebSocket synchronization loop.
  """
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

  @doc """
  Processes real-time messages dispatched inside multi-user rooms.
  """
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
end

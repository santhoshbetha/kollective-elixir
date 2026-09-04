# Receives the Base64-encoded encrypted AES key and the file path from React once the upload is finished
defmodule KollectiveWeb.MessageController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Chats.Chats
  alias Kollective.Chats.Participant

  # 🟢 NEW: HISTORICAL MESSAGE RETRIEVAL (PULL STRATEGY)
  def index1(conn, %{"conversation_id" => conversation_id}) do
    current_user_id = conn.assigns.current_user.id

    # Security Guard check: Make sure they aren't snooping on someone else's DM
    if Chats.is_participant?(conversation_id, current_user_id) do
      # Uses your exact context function that outputs {messages, other_participant_last_read}
      {messages, other_last_read} =
        Chats.list_messages_with_read_status(conversation_id, current_user_id)

      # Render lists via MessageJSON index/1 function
      # Passing the 'other_last_read_at' parameter inside the layout conn assigns metadata if needed
      render(conn, :index, messages: messages, other_participant_last_read: other_last_read)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You are not authorized to view this chat history."})
    end
  end

  def index(conn, %{"conversation_id" => conversation_id} = params) do
    current_user_id = conn.assigns.current_user.id

    if Chats.is_participant?(conversation_id, current_user_id) do
      # Parse optional cursor query configurations cleanly from request strings
      limit = Map.get(params, "limit", "20") |> String.to_integer()
      before_id = Map.get(params, "before_id")

      {messages, other_last_read} =
        Chats.list_messages_cursor(conversation_id, current_user_id,
          limit: limit,
          before_id: before_id
        )

      # Extract the oldest message ID on this page to serve as the 'next_cursor'
      next_cursor =
        case List.first(messages) do
          nil -> nil
          first_msg -> first_msg.id
        end

      # Output data array alongside page configuration blocks
      render(conn, :index,
        messages: messages,
        other_participant_last_read: other_last_read,
        next_cursor: next_cursor
      )
    else
      conn |> put_status(:forbidden) |> json(%{error: "Unauthorized access path."})
    end
  end

  def create(conn, %{"conversation_id" => conv_id, "message" => msg_params}) do
    user_id = conn.assigns.current_user.id

    case Chats.create_message_with_attachment(user_id, conv_id, msg_params) do
      # Matches the exact tuple map shape returned by your Ecto.Multi transaction
      {:ok, %{message: message}} ->
        # 1. Deliver content over the specific chat WebSocket line
        broadcast_new_message(message)

        # 2. 📣 EXTRA REAL-TIME ENHANCEMENT:
        # Push a silent unread badge signal to the recipient's notification line
        trigger_unread_badge_bump(user_id, conv_id)

        conn
        |> put_status(:created)
        |> render(:show, message: message)

      {:error, _failed_operation, changeset, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  defp broadcast_new_message(message) do
    topic = "conversation:#{message.conversation_id}"

    payload = %{
      id: message.id,
      sender_id: message.sender_id,
      conversation_id: message.conversation_id,
      encrypted_content: message.encrypted_content,
      file_url: message.file_url,
      inserted_at: message.inserted_at
    }

    # Atomic deliver out to the explicit conversation timeline
    KollectiveWeb.Endpoint.broadcast!(topic, "new_message", payload)
  end

  defp trigger_unread_badge_bump(sender_id, conversation_id) do
    # Find the OTHER participant's ID inside this chat room
    recipient_id =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.one()

    if recipient_id do
      # Compute their fresh global count using your exact get_unread_count/2 function
      unread_count = Chats.get_unread_count(conversation_id, recipient_id)

      alert_payload = %{
        type: "dm_badge_update",
        conversation_id: conversation_id,
        unread_count: unread_count
      }

      # Broadcast to their secure private background notification channel!
      KollectiveWeb.Endpoint.broadcast(
        "user_notifications:#{recipient_id}",
        "new_alert",
        alert_payload
      )
    end
  end
end

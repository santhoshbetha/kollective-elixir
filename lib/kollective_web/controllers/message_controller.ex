# Receives the Base64-encoded encrypted AES key and the file path from React once the upload is finished
defmodule KollectiveWeb.MessageController do
  use KollectiveWeb, :controller
  alias Kollective.Chats.Chats

  def create(conn, %{"conversation_id" => conv_id, "message" => msg_params}) do
    user_id = conn.assigns.current_user.id

    case Chats.create_message_with_attachment(user_id, conv_id, msg_params) do
      {:ok, %{message: message}} ->
        # Broadcast to the recipient's WebSocket
        broadcast_new_message(message)

        conn |> put_status(:created) |> render(:show, message: message)

      {:error, _failed_operation, changeset, _} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  # Why use Endpoint.broadcast!?
  # Context-Agnostic: Since your create action happens in a Controller, you don't have a socket struct.
  #                   The Endpoint module allows you to send messages to any topic from anywhere in your app.
  # Atomic Delivery: The ! version ensures that if the internal PubSub fails (rare), it raises an error,
  #                  allowing your transaction to fail gracefully rather than silently dropping a message.
  defp broadcast_new_message(message) do
    # 1. Define the topic for this specific conversation
    topic = "conversation:#{message.conversation_id}"

    # 2. Construct the payload
    # Includes the RSA-encrypted AES key and the R2 file path
    payload = %{
      id: message.id,
      sender_id: message.sender_id,
      encrypted_content: message.encrypted_content,
      file_url: message.file_url,
      encrypted_file_key: message.encrypted_file_key,
      file_iv: message.file_iv,
      file_name: message.file_name,
      inserted_at: message.inserted_at
    }

    # 3. Use the Endpoint to broadcast from outside a channel process
    KollectiveWeb.Endpoint.broadcast!(topic, "new_message", payload)
  end
end

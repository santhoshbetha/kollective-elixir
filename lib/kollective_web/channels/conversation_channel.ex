defmodule KollectiveWeb.ConversationChannel do
  use KollectiveWeb, :channel
  alias Kollective.Chats.Chats

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

  @impl true
  def handle_in("read_receipt", _payload, socket) do
    conversation_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    # 🟢 ALIGNED: Runs your high-speed atomic Repo.update_all/2 reset pass
    {1, _} = Chats.mark_as_read(conversation_id, user_id)

    # Broadcast read confirmation back out over the room WebSocket to your partner
    broadcast!(socket, "message_read", %{
      conversation_id: conversation_id,
      reader_id: user_id,
      read_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    {:reply, :ok, socket}
  end
end

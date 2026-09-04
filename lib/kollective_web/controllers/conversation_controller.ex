defmodule KollectiveWeb.ConversationController do
  use KollectiveWeb, :controller
  alias Kollective.Chats.Chats

  def index(conn, _params) do
    current_user_id = conn.assigns.current_user.id

    # 1. Fetch recent rooms using your exact context function query blueprint
    # This query automatically preloads the last message and other participant profiles
    query = Chats.list_my_conversations(current_user_id)
    conversations = Kollective.Repo.all(query)

    # 2. Serialize and output
    # You can map this into a custom ConversationJSON view or output a clean direct map block:
    serialized_inbox =
      Enum.map(conversations, fn c ->
        # Find the last message safely if it exists
        last_msg = List.first(c.messages)

        # Isolate the *other* participant's user information
        other_party =
          Enum.find(c.participants, fn p -> p.user_id != current_user_id end)
          |> case do
            nil ->
              %{username: "Deleted User", avatar: nil}

            participant ->
              %{username: participant.user.username, avatar: participant.user.avatar_url}
          end

        %{
          id: c.id,
          updated_at: c.updated_at,
          unread_count: Chats.get_unread_count(c.id, current_user_id),
          other_user: other_party,
          last_message:
            if(last_msg,
              do: %{
                sender_id: last_msg.sender_id,
                encrypted_content: last_msg.encrypted_content,
                inserted_at: last_msg.inserted_at
              },
              else: nil
            )
        }
      end)

    json(conn, %{data: serialized_inbox})
  end
end

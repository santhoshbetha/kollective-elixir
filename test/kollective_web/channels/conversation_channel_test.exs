defmodule KollectiveWeb.ConversationChannelTest do
  use Kollective.DataCase, async: false
  import Phoenix.ChannelTest
  import Kollective.Factory

  @endpoint KollectiveWeb.Endpoint

  alias KollectiveWeb.UserSocket
  alias KollectiveWeb.ConversationChannel
  alias Kollective.Chats.{Conversation, Participant}
  alias Kollective.Repo

  setup do
    user1 = insert(:user, username: "alice")
    user2 = insert(:user, username: "bob")

    conversation =
      %Conversation{}
      |> Conversation.changeset(%{
        "title" => "Direct Chat",
        "participants" => [
          %{"user_id" => user1.id},
          %{"user_id" => user2.id}
        ]
      })
      |> Repo.insert!()

    {:ok, socket} =
      connect(UserSocket, %{
        "token" => Kollective.Accounts.Accounts.generate_user_session_token(user1)
      })

    {:ok, _, socket} =
      subscribe_and_join(socket, ConversationChannel, "conversation:#{conversation.id}")

    %{socket: socket, user1: user1, user2: user2, conversation: conversation}
  end

  test "mark_delivered handles payload and broadcasts delivery_receipt_bump", %{
    socket: socket,
    user1: user1,
    conversation: conversation
  } do
    ref =
      push(socket, "mark_delivered", %{
        "message_ids" => ["msg_001", "msg_002"]
      })

    assert_reply ref, :ok

    assert_broadcast "delivery_receipt_bump", %{
      user_id: user_id,
      conversation_id: conv_id,
      message_ids: ["msg_001", "msg_002"]
    }

    assert user_id == to_string(user1.id)
    assert conv_id == to_string(conversation.id)

    # Participant last_delivered_at should now be populated in the database
    participant = Repo.get_by(Participant, user_id: user1.id, conversation_id: conversation.id)
    assert participant.last_delivered_at != nil
  end

  test "typing_heartbeat broadcasts typing_receipt_broadcast without crashing", %{
    socket: socket,
    user1: user1
  } do
    push(socket, "typing_heartbeat", %{"is_typing" => true})

    assert_broadcast "typing_receipt_broadcast", %{
      user_id: user_id,
      is_typing: true
    }

    assert user_id == to_string(user1.id)
  end

  test "unhandled events are safely ignored by the fallback clause", %{socket: socket} do
    _ref = push(socket, "some_unknown_event", %{"foo" => "bar"})
    # GenServer does not crash and stays alive
    Process.sleep(50)
    assert Process.alive?(socket.channel_pid)
  end
end

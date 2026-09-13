defmodule KollectiveWeb.ConversationJSONTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  alias Kollective.Chats.Conversation
  alias KollectiveWeb.ConversationJSON

  describe "ConversationJSON serialization" do
    setup do
      user = insert(:user)
      other_user = insert(:user)
      conversation = insert(:conversation)

      _p1 = insert(:chat_participant, user: user, conversation: conversation)
      _p2 = insert(:chat_participant, user: other_user, conversation: conversation)

      msg =
        insert(:chat_message,
          conversation: conversation,
          sender_id: other_user.id,
          encrypted_content: "Encrypted payload"
        )

      conversation =
        Conversation
        |> Kollective.Repo.get!(conversation.id)
        |> Kollective.Repo.preload([:messages, participants: [:user]])

      {:ok,
       current_user_id: user.id, other_user: other_user, conversation: conversation, msg: msg}
    end

    test "data/2 serializes conversation with other user and last message", %{
      current_user_id: current_user_id,
      other_user: other_user,
      conversation: conversation
    } do
      data = ConversationJSON.data(conversation, current_user_id)

      assert data.id == conversation.id
      assert data.other_user.username == other_user.username
      assert data.other_user.avatar == other_user.avatar_url
      assert data.last_message.sender_id == other_user.id
      assert data.last_message.encrypted_content == "Encrypted payload"
      assert data.unread_count == 1
    end

    test "index/2 serializes list of conversations", %{
      current_user_id: current_user_id,
      conversation: conversation
    } do
      items = ConversationJSON.index([conversation], current_user_id)

      assert length(items) == 1
      assert hd(items).id == conversation.id
    end

    test "show/1 wraps data in map", %{
      current_user_id: current_user_id,
      conversation: conversation
    } do
      rendered =
        ConversationJSON.show(%{conversation: conversation, current_user_id: current_user_id})

      assert rendered.data.id == conversation.id
    end

    test "handles deleted/missing other user safely", %{current_user_id: current_user_id} do
      user = Kollective.Repo.get!(Kollective.Accounts.User, current_user_id)
      conv = insert(:conversation)
      _p = insert(:chat_participant, user: user, conversation: conv)

      conv =
        Conversation
        |> Kollective.Repo.get!(conv.id)
        |> Kollective.Repo.preload([:messages, participants: [:user]])

      data = ConversationJSON.data(conv, current_user_id)

      assert data.other_user.username == "Deleted User"
      assert data.other_user.avatar == nil
      assert data.last_message == nil
    end
  end
end

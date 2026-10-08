defmodule KollectiveWeb.MessageControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  setup :authenticate_user

  setup %{conn: conn, user: user} do
    # Create another user to talk to
    other_user = insert(:user)

    # Create a conversation
    conversation = insert(:conversation)

    # Add both users as participants to satisfy participant checks and unread counter joins
    _p1 = insert(:chat_participant, user: user, conversation: conversation)
    _p2 = insert(:chat_participant, user: other_user, conversation: conversation)

    {:ok, conn: conn, user: user, other_user: other_user, conversation: conversation}
  end

  describe "GET /api/v1/conversations/:conversation_id/messages" do
    test "lists messages for a valid conversation participant", %{
      conn: conn,
      user: user,
      conversation: conversation
    } do
      # Insert messages into the conversation
      m1 = insert(:chat_message, sender_id: user.id, conversation: conversation)
      m2 = insert(:chat_message, sender_id: user.id, conversation: conversation)

      response =
        conn
        |> get(~p"/api/v1/conversations/#{conversation.id}/messages")
        |> json_response(200)

      assert is_list(response["data"])
      assert length(response["data"]) == 2

      ids = Enum.map(response["data"], fn msg -> msg["id"] end)
      assert m1.id in ids
      assert m2.id in ids
    end

    test "supports keyset cursor pagination with before_id and limit", %{
      conn: conn,
      user: user,
      conversation: conversation
    } do
      m1 = insert(:chat_message, sender_id: user.id, conversation: conversation)
      m2 = insert(:chat_message, sender_id: user.id, conversation: conversation)

      response =
        conn
        |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
          "limit" => "1",
          "before_id" => to_string(m2.id)
        })
        |> json_response(200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == m1.id
      assert response["pagination"]["next_cursor"] == to_string(m1.id)
    end

    test "returns 403 forbidden for non-participants", %{conversation: conversation} do
      # Create a new user that is NOT a participant of this conversation
      non_member = insert(:user)
      non_member_conn = authenticate_conn(build_conn(), non_member)

      response =
        non_member_conn
        |> get(~p"/api/v1/conversations/#{conversation.id}/messages")
        |> json_response(403)

      assert response["error"] =~ "Unauthorized access path"
    end
  end

  describe "POST /api/v1/conversations/:conversation_id/messages" do
    test "creates a new message successfully and broadcasts it", %{
      conn: conn,
      conversation: conversation
    } do
      # Subscribe to the PubSub channel to assert real-time websocket delivery
      topic = "conversation:#{conversation.id}"
      KollectiveWeb.Endpoint.subscribe(topic)

      params = %{
        "message" => %{
          "encrypted_content" => "This is my encrypted text"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/conversations/#{conversation.id}/messages", params)
        |> json_response(201)

      assert response["data"]["encrypted_content"] == "This is my encrypted text"

      # Assert the websocket Endpoint broadcast message was delivered to subscribers
      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "new_message",
        payload: %{encrypted_content: "This is my encrypted text"}
      }

      # Unsubscribe cleanly
      KollectiveWeb.Endpoint.unsubscribe(topic)
    end

    test "returns 422 with validation errors for invalid params", %{
      conn: conn,
      conversation: conversation
    } do
      params = %{
        "message" => %{
          "encrypted_content" => %{"invalid" => "map"}
        }
      }

      response =
        conn
        |> post(~p"/api/v1/conversations/#{conversation.id}/messages", params)
        |> json_response(422)

      assert response["errors"]["encrypted_content"]
    end
  end
end

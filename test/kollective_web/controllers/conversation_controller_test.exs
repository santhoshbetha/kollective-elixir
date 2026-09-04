defmodule KollectiveWeb.ConversationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  describe "unauthenticated conversation endpoints" do
    test "GET /api/conversations returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/conversations")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "authenticated conversation endpoints" do
    setup :authenticate_user

    test "GET /api/conversations returns empty array when no conversations exist", %{
      conn: conn
    } do
      response =
        conn
        |> get(~p"/api/conversations")
        |> json_response(200)

      assert response["status"] == "success" || !Map.has_key?(response, "status")
      assert response["data"] == []
    end

    test "GET /api/conversations returns active conversations with last message and unread counts",
         %{conn: conn, user: user} do
      # Create conversation and participant records
      other_user = insert(:user)
      conversation = insert(:conversation)

      # Insert participant for current user
      _p1 = insert(:chat_participant, user: user, conversation: conversation)
      # Insert participant for other user
      _p2 = insert(:chat_participant, user: other_user, conversation: conversation)

      # Create a message sent by other user
      _message =
        insert(:chat_message,
          conversation: conversation,
          sender_id: other_user.id,
          encrypted_content: "Hello there!"
        )

      response =
        conn
        |> get(~p"/api/conversations")
        |> json_response(200)

      assert length(response["data"]) == 1
      [conv_json] = response["data"]

      assert conv_json["id"] == conversation.id
      assert conv_json["other_user"]["username"] == other_user.username
      assert conv_json["other_user"]["avatar"] == other_user.avatar_url
      assert conv_json["last_message"]["sender_id"] == other_user.id
      assert conv_json["last_message"]["encrypted_content"] == "Hello there!"
      # Since last_read_at is nil for p1, the message counts as unread
      assert conv_json["unread_count"] == 1
    end
  end
end

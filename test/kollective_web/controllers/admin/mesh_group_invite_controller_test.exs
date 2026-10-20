defmodule KollectiveWeb.Admin.MeshGroupInviteControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Chats.{Conversation, Participant}

  setup %{conn: conn} do
    creator = insert(:user)

    conversation =
      %Conversation{}
      |> Conversation.changeset(%{
        "title" => "Central Dispatch Room",
        "participants" => [%{"user_id" => creator.id}]
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, creator)
      |> assign(:user, creator)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, creator: creator, conversation: conversation}
  end

  describe "MeshGroupInviteController invite" do
    test "adds user to active conversation and broadcasts event", %{
      conn: conn,
      conversation: conversation
    } do
      invitee = insert(:user, username: "operator_dave", display_name: "Dave Operator")

      payload = %{
        "username" => "operator_dave"
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups/#{conversation.id}/invite", payload)
      assert json_response(conn, 201)["status"] == "success"

      # Verify participant in DB
      participant =
        Repo.get_by(Participant, user_id: invitee.id, conversation_id: conversation.id)

      assert participant != nil
    end

    test "returns 404 when user handle does not exist", %{conn: conn, conversation: conversation} do
      payload = %{
        "username" => "non_existent_ghost"
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups/#{conversation.id}/invite", payload)
      assert response = json_response(conn, 404)
      assert response["error"] =~ "Citizen account mapping profile not found"
    end

    test "returns 409 conflict when user is already participant", %{
      conn: conn,
      conversation: conversation,
      creator: creator
    } do
      # Creator is already participant in setup
      payload = %{
        "username" => creator.username
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups/#{conversation.id}/invite", payload)
      assert response = json_response(conn, 409)
      assert response["error"] =~ "already a registered participant"
    end
  end

  describe "MeshGroupInviteController index" do
    test "lists participants with profile metadata", %{
      conn: conn,
      conversation: conversation,
      creator: creator
    } do
      conn = get(conn, ~p"/api/v1/admin/chat_groups/#{conversation.id}/members")
      assert %{"data" => members} = json_response(conn, 200)

      member_ids = Enum.map(members, & &1["id"])
      assert to_string(creator.id) in member_ids
    end
  end
end

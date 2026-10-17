defmodule KollectiveWeb.Admin.MeshGroupChatControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Chats.Conversation

  setup %{conn: conn} do
    # Clear Mnesia table if exists
    if :distributed_chat_groups in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:distributed_chat_groups)
    end

    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "MeshGroupChatController create" do
    test "creates chat group in Postgres and registers in Mnesia mesh table", %{conn: conn, user: user} do
      invitee_a = insert(:user)
      invitee_b = insert(:user)

      payload = %{
        "group" => %{
          "title" => "Decentralized Governance WG",
          "description" => "Coordination group for mesh operators",
          "invitee_ids" => [invitee_a.id, invitee_b.id]
        }
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups", payload)
      assert %{"status" => "success", "data" => data} = json_response(conn, 201)

      conv_id = data["id"]
      assert data["title"] == "Decentralized Governance WG"

      # Verify Postgres conversation and participants
      conversation = Repo.get!(Conversation, conv_id) |> Repo.preload(:participants)
      assert conversation.title == "Decentralized Governance WG"
      participant_user_ids = Enum.map(conversation.participants, & &1.user_id)
      assert user.id in participant_user_ids
      assert invitee_a.id in participant_user_ids
      assert invitee_b.id in participant_user_ids

      # Verify Mnesia replicated group entry
      assert {:atomic, [record]} =
               :mnesia.transaction(fn -> :mnesia.read(:distributed_chat_groups, conv_id) end)

      assert {:distributed_chat_groups, ^conv_id, "Decentralized Governance WG",
              "Coordination group for mesh operators", "cause", _inserted_at} = record
    end

    test "creates chat group with direct parameters without nested group wrapper", %{conn: conn, user: user} do
      payload = %{
        "title" => "Direct Topic",
        "description" => "Direct description"
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups", payload)
      assert %{"status" => "success", "data" => data} = json_response(conn, 201)

      conv_id = data["id"]
      conversation = Repo.get!(Conversation, conv_id) |> Repo.preload(:participants)
      assert conversation.title == "Direct Topic"
      assert Enum.any?(conversation.participants, &(&1.user_id == user.id))
    end

    test "returns 422 when title is missing", %{conn: conn} do
      payload = %{
        "group" => %{
          "description" => "No title provided"
        }
      }

      conn = post(conn, ~p"/api/v1/admin/chat_groups", payload)
      assert response = json_response(conn, 422)
      assert response["error"] =~ "Failed to allocate relational group boundaries"
      assert response["details"]["title"] != nil
    end
  end
end

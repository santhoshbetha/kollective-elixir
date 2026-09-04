# test/kollective_web/controllers/relationship_controller_test.exs
defmodule KollectiveWeb.RelationshipControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    # Standard JSON API token assignment matching your project baseline
    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "index/2 (GET /api/v1/relationships)" do
    test "returns a successfully serialized list for valid relationship lookups", %{
      conn: conn,
      user: user
    } do
      target_user = insert(:user)
      # Seed an explicit block entry to satisfy context queries
      insert(:user_relationship, source_id: user.id, target_id: target_user.id, type: "block")

      response =
        conn
        |> get(~p"/api/v1/relationships", %{"type" => "block"})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
    end

    test "returns 400 bad_request when passing unmapped relationship parameters", %{conn: conn} do
      response =
        conn
        |> get(~p"/api/v1/relationships", %{"type" => "invalid_relationship_type"})
        |> json_response(400)

      assert response["error"] =~ "Invalid relationship listing type"
    end
  end

  describe "toggle/2 (POST /api/v1/relationships/toggle)" do
    test "successfully inserts a social graph edge link when no relationship exists", %{
      conn: conn
    } do
      target_user = insert(:user)
      params = %{"target_id" => target_user.id, "type" => "follow"}

      response =
        conn
        |> post(~p"/api/v1/relationships/toggle", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "inserted"
      assert response["relationship_state"] == "follow"
    end

    test "successfully purges a social graph edge link when a match already exists", %{
      conn: conn,
      user: user
    } do
      target_user = insert(:user)
      # Simulate a relationship already active prior to the click
      insert(:user_relationship, source_id: user.id, target_id: target_user.id, type: "follow")

      params = %{"target_id" => target_user.id, "type" => "follow"}

      response =
        conn
        |> post(~p"/api/v1/relationships/toggle", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "removed"
      assert response["relationship_state"] == "none"
    end

    test "returns 422 unprocessable_entity on self-referencing operations", %{
      conn: conn,
      user: user
    } do
      params = %{"target_id" => user.id, "type" => "block"}

      response =
        conn
        |> post(~p"/api/v1/relationships/toggle", params)
        |> json_response(422)

      assert response["error"] =~ "Self-referencing actions are blocked"
    end

    test "returns 400 bad_request when toggle schema action fields are malformed", %{conn: conn} do
      params = %{"target_id" => Ecto.ULID.generate(), "type" => "prohibited_action"}

      response =
        conn
        |> post(~p"/api/v1/relationships/toggle", params)
        |> json_response(400)

      assert response["error"] =~ "Prohibited configuration signature"
    end
  end
end

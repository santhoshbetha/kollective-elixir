# test/kollective_web/controllers/poll_controller_test.exs
defmodule KollectiveWeb.PollControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "show/2 (GET /api/v1/polls/:id)" do
    test "renders poll details successfully when matching record exists", %{conn: conn} do
      # ⚡ Inserts a real poll record into PostgreSQL using a valid Ecto.ULID
      poll = insert(:poll)

      response =
        conn
        |> get(~p"/api/v1/polls/#{poll.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["poll"]["id"] == poll.id
    end

    test "returns 404 not_found when target poll does not exist", %{conn: conn} do
      # ⚡ FIXED: Generates a structurally valid random ULID string to bypass cast crashes safely
      random_ulid = Ecto.ULID.generate()

      response =
        conn
        |> get(~p"/api/v1/polls/#{random_ulid}")
        |> json_response(404)

      assert response["error"] == "Poll not found"
    end
  end
end

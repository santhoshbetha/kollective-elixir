# test/kollective_web/controllers/feed_controller_test.exs
defmodule KollectiveWeb.FeedControllerTest do
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

  describe "home/2 (GET /api/v1/timeline/home)" do
    test "returns serialized home timeline entries using PostJSON", %{conn: conn} do
      _post = insert(:post)

      response =
        conn
        |> get(~p"/api/v1/timeline/home")
        |> json_response(200)

      assert is_list(response["data"])
    end
  end

  describe "feed/2 (GET /api/v1/communities/feed)" do
    test "returns serialized community posts using PostJSON", %{conn: conn} do
      response =
        conn
        |> get(~p"/api/v1/communities/feed", %{"scope" => "local"})
        |> json_response(200)

      assert is_list(response["data"])
    end
  end
end

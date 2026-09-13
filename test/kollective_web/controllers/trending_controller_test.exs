# test/kollective_web/controllers/trending_controller_test.exs
defmodule KollectiveWeb.TrendingControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Hashtags.Hashtag

  setup %{conn: conn} do
    user = Kollective.Factory.insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "index/2 (GET /api/v1/trending/tags)" do
    test "returns trending hashtags serialized via HashtagJSON", %{conn: conn} do
      %Hashtag{name: "tech"} |> Repo.insert!()

      response =
        conn
        |> get(~p"/api/v1/trending/tags")
        |> json_response(200)

      assert is_list(response["data"])
    end
  end
end

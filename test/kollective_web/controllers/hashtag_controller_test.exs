# test/kollective_web/controllers/hashtag_controller_test.exs
defmodule KollectiveWeb.HashtagControllerTest do
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

  describe "show/2 (GET /api/v1/timelines/tag/:tag)" do
    test "returns a successfully serialized timeline of posts for a valid hashtag", %{
      conn: conn,
      user: user
    } do
      # ⚡ FIXED: Seed a real post matching your layout directly into PostgreSQL
      _post = insert(:post, author: user, content: "Testing #elixir rules!")

      response =
        conn
        |> get(~p"/api/v1/timelines/tag/elixir")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["tag"] == "elixir"
      assert is_list(response["data"])
    end
  end

  describe "show_by_query/2 (GET /api/discovery/hashtag)" do
    test "extracts tag parameter from URL query string and strips whitespace gracefully", %{
      conn: conn
    } do
      response =
        conn
        |> get(~p"/api/v1/discovery/hashtag", %{"tag" => "  PHOENIX  "})
        |> json_response(200)

      assert response["status"] == "success"
      assert response["tag"] == "phoenix"
      assert is_list(response["data"])
    end

    test "falls back to 400 bad_request guard block when tag query parameter is missing", %{
      conn: conn
    } do
      response =
        conn
        |> get(~p"/api/v1/discovery/hashtag", %{"malformed_key" => "value"})
        |> json_response(400)

      assert response["status"] == "error"
      assert response["code"] == "missing_tag_parameter"
      assert response["message"] =~ "You must provide a valid 'tag' parameter"
    end
  end

  describe "follow/2 and unfollow/2 (POST /api/v1/tags/:tag/follow and unfollow)" do
    test "successfully follows and unfollows a hashtag by tag name", %{conn: conn} do
      follow_res =
        conn
        |> post(~p"/api/v1/tags/elixir/follow")
        |> json_response(200)

      assert follow_res["name"] == "elixir"
      assert follow_res["following"] == true

      tags_res =
        conn
        |> get(~p"/api/v1/followed_tags")
        |> json_response(200)

      assert Enum.any?(tags_res, fn t -> t["name"] == "elixir" end)

      unfollow_res =
        conn
        |> post(~p"/api/v1/tags/elixir/unfollow")
        |> json_response(200)

      assert unfollow_res["name"] == "elixir"
      assert unfollow_res["following"] == false
    end
  end
end

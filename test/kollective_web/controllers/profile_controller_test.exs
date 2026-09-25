defmodule KollectiveWeb.ProfileControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures

  setup do
    user = user_fixture(%{username: "city_planning_test"})
    {:ok, user: user}
  end

  describe "GET /api/v1/accounts/:username_or_id/posts" do
    test "returns user posts for a valid username", %{conn: conn, user: user} do
      {:ok, post} =
        Kollective.Posts.Posts.create_post(user, %{
          "content" => "<p>City planning update</p>",
          "text" => "City planning update",
          "category" => "post",
          "target_scope" => "world",
          "visibility" => "public"
        })

      conn = get(conn, ~p"/api/v1/accounts/#{user.username}/posts?limit=20&exclude_replies=true")

      assert json = json_response(conn, 200)
      assert json["status"] == "success"
      assert is_list(json["data"])
      assert length(json["data"]) == 1
      assert hd(json["data"])["id"] == to_string(post.id)
    end

    test "returns 404 for non-existent account", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/accounts/non_existent_account_12345/posts")

      assert json = json_response(conn, 404)
      assert json["error"] == "not_found"
    end
  end
end

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

  describe "GET /api/v1/profile/media/presign" do
    setup %{conn: conn, user: user} do
      authenticated_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:current_user, user)
        |> assign(:current_scope, %{user: user})

      {:ok, conn: authenticated_conn}
    end

    test "generates presigned upload tickets for 'event' banner asset type", %{conn: conn} do
      params = %{"filename" => "summit_banner.jpg", "type" => "event", "content_type" => "image/jpeg"}

      response =
        conn
        |> get(~p"/api/v1/profile/media/presign", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert is_binary(response["upload_url"])
      assert is_binary(response["final_asset_url"])

      expected_prefix = Kollective.Storage.prefix()
      assert response["upload_url"] =~ expected_prefix
      assert response["final_asset_url"] =~ expected_prefix
      assert response["final_asset_url"] =~ "/event/"
    end

    test "generates presigned upload tickets for 'business' profile asset type", %{conn: conn} do
      params = %{"filename" => "storefront.png", "type" => "business", "content_type" => "image/png"}

      response =
        conn
        |> get(~p"/api/v1/profile/media/presign", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert is_binary(response["upload_url"])
      assert is_binary(response["final_asset_url"])

      expected_prefix = Kollective.Storage.prefix()
      assert response["upload_url"] =~ expected_prefix
      assert response["final_asset_url"] =~ expected_prefix
      assert response["final_asset_url"] =~ "/business/"
    end

    test "strictly isolates uploaded profile and event assets under test storage prefix", %{conn: conn} do
      for asset_type <- ["avatar", "banner", "event", "business"] do
        params = %{"filename" => "image.png", "type" => asset_type, "content_type" => "image/png"}

        response =
          conn
          |> get(~p"/api/v1/profile/media/presign", params)
          |> json_response(200)

        expected_prefix = Kollective.Storage.prefix()
        assert response["upload_url"] =~ expected_prefix
        assert response["final_asset_url"] =~ expected_prefix
      end
    end

    test "rejects unsupported asset type with 400 bad_request", %{conn: conn} do
      params = %{"filename" => "malicious.exe", "type" => "unsupported_type", "content_type" => "application/octet-stream"}

      response =
        conn
        |> get(~p"/api/v1/profile/media/presign", params)
        |> json_response(400)

      assert response["error"] == "Invalid asset type parameters."
    end
  end
end

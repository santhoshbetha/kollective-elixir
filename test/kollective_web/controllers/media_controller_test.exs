# test/kollective_web/controllers/media_controller_test.exs


defmodule KollectiveWeb.MediaControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    # Clean JSON API token mock session layer mapping layout
    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "presign/2 (GET /api/v1/media/presign)" do
    test "generates Cloudflare R2 secure write ticket signatures successfully", %{conn: conn} do
      params = %{"filename" => "vacation.png", "content_type" => "image/png"}

      response =
        conn
        |> get(~p"/api/v1/media/presign", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert is_binary(response["upload_url"])
      assert response["final_asset_url"] =~ Kollective.Storage.cdn_domain()
    end

    test "strictly isolates uploaded object keys under the test prefix", %{conn: conn} do
      params = %{"filename" => "mountain.png", "content_type" => "image/png"}

      response =
        conn
        |> get(~p"/api/v1/media/presign", params)
        |> json_response(200)

      expected_prefix = Kollective.Storage.prefix()
      assert response["upload_url"] =~ expected_prefix
      assert response["final_asset_url"] =~ expected_prefix
    end
  end

  describe "attachment binding via Posts.create_post" do
    test "binds pre-uploaded media_ids and updates their description from imageAlts", %{user: user} do
      att1 = insert(:post_attachment, user: user, user_id: user.id, url: "/media/test/1.png")
      att2 = insert(:post_attachment, user: user, user_id: user.id, url: "/media/test/2.png")

      post_attrs = %{
        "content" => "Post with images!",
        "media_ids" => [att1.id, att2.id],
        "imageAlts" => ["a test mountain", "a test river"]
      }

      assert {:ok, post} = Kollective.Posts.Posts.create_post(user, post_attrs)

      serialized = KollectiveWeb.PostJSON.show(post)
      assert length(serialized.images) == 2

      [img1, img2] = serialized.images
      assert img1.url == "/media/test/1.png"
      assert img1.description == "a test mountain"
      assert img2.url == "/media/test/2.png"
      assert img2.description == "a test river"
    end
  end

  describe "create/2 (POST /api/v1/media)" do
    test "inserts an orphaned attachment mapping node on valid direct-to-cloud payloads", %{
      conn: conn
    } do
      params = %{
        "media" => %{
          "url" => "https://r2.devtest_image.jpg",
          "media_type" => "image/jpeg",
          "blurhash" => "L6PZfsi_00Kj%~j[fQj["
        }
      }

      response =
        conn
        |> post(~p"/api/v1/media", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["url"] == "https://r2.devtest_image.jpg"
      assert response["data"]["type"] == "image"
      assert String.length(response["data"]["id"]) == 26
    end
  end

  describe "update/2 (PUT /api/v1/media/:id)" do
    setup %{user: user} do
      # Pass the explicit authenticated setup user record directly to the factory
      attachment = insert(:post_attachment, user: user, user_id: user.id)
      {:ok, attachment: attachment}
    end

    test "modifies description caption payload when requester is the original uploader", %{
      conn: conn,
      attachment: attachment
    } do
      params = %{"description" => "A group photo at the park meetup."}

      response =
        conn
        |> put(~p"/api/v1/media/#{attachment.id}", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["description"] == "A group photo at the park meetup."
    end

    test "returns 403 forbidden if another user attempts to update metadata description", %{
      conn: conn
    } do
      other_user = insert(:user)
      other_attachment = insert(:post_attachment, user: other_user, user_id: other_user.id)

      params = %{"description" => "Malicious Hijack Description"}

      response =
        conn
        |> put(~p"/api/v1/media/#{other_attachment.id}", params)
        |> json_response(403)

      assert response["error"] == "unauthorized"
    end
  end

  describe "show/2 (GET /api/v1/media/:id)" do
    test "retrieves discrete attachment configuration details from database", %{
      conn: conn,
      user: user
    } do
      attachment =
        insert(:post_attachment,
          user: user,
          user_id: user.id,
          url: "https://r2.dev",
          media_type: "video/mp4"
        )

      response =
        conn
        |> get(~p"/api/v1/media/#{attachment.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["url"] == "https://r2.dev"
      # Verifies your private serialization mapper runs smoothly
      assert response["data"]["type"] == "video"
    end

    test "returns 404 not_found on missing identifier lookups", %{conn: conn} do
      random_ulid = Ecto.ULID.generate()

      response =
        conn
        |> get(~p"/api/v1/media/#{random_ulid}")
        |> json_response(404)

      assert response["error"] =~ "not found"
    end
  end
end

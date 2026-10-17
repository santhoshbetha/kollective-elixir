defmodule KollectiveWeb.StorageControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    user =
      insert(:user,
        email: "storage_#{System.unique_integer([:positive])}@test.com",
        username: "storage_user_#{System.unique_integer([:positive])}",
        identity_hash: "hash_#{System.unique_integer([:positive])}"
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v1/chat/presign" do
    test "generates a presigned URL for a valid file size", %{conn: conn} do
      payload = %{"file_size" => 1024 * 1024}

      conn = post(conn, ~p"/api/v1/chat/presign", payload)

      assert %{
               "upload_url" => upload_url,
               "public_file_url" => public_url
             } = json_response(conn, 200)

      assert upload_url =~ "https://"
      assert upload_url =~ "chats/attachments/"
      assert public_url =~ ".enc"
    end

    test "returns 422 when file size exceeds the 20MB limit", %{conn: conn} do
      payload = %{"file_size" => 25 * 1024 * 1024}

      conn = post(conn, ~p"/api/v1/chat/presign", payload)

      assert json_response(conn, 422)["error"] =~ "Must provide valid size under 20MB"
    end

    test "returns 422 when file_size parameter is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/chat/presign", %{})

      assert json_response(conn, 422)["error"] =~ "Must provide valid size under 20MB"
    end
  end
end

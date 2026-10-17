defmodule KollectiveWeb.Admin.MultiRegionStorageControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    id = System.unique_integer([:positive])

    user =
      insert(:user,
        country: "US",
        email: "mr_storage_#{id}@test.com",
        username: "mr_user_#{id}",
        identity_hash: "hash_#{id}"
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "MultiRegionStorageController presign" do
    test "presigns upload URL and maps to US-east bucket for US user", %{conn: conn} do
      payload = %{
        "content_type" => "image/jpeg",
        "file_size" => 204_800
      }

      conn = post(conn, ~p"/api/v1/storage/presign", payload)
      assert %{"data" => data} = json_response(conn, 200)

      assert data["allocated_region"] == "kollective-vault-us-east"
      assert data["file_size"] == 204_800
      assert data["upload_url"] =~ "kollective-vault-us-east"
      assert data["public_file_url"] =~ "https://kollective.app/chats/attachments/"
      assert data["object_key"] =~ "chats/attachments/"
    end

    test "presigns upload URL targeting AP-South for user in India", %{conn: conn} do
      user_in = insert(:user, country: "IN")

      conn =
        conn
        |> assign(:current_user, user_in)
        |> assign(:user, user_in)

      payload = %{
        "content_type" => "video/mp4",
        "file_size" => 5_242_880
      }

      conn = post(conn, ~p"/api/v1/storage/presign", payload)
      assert %{"data" => data} = json_response(conn, 200)

      assert data["allocated_region"] == "kollective-vault-ap-south"
      assert data["upload_url"] =~ "kollective-vault-ap-south"
    end

    test "presigns upload URL targeting EU-Central for European user", %{conn: conn} do
      user_eu = insert(:user, country: "DE")

      conn =
        conn
        |> assign(:current_user, user_eu)
        |> assign(:user, user_eu)

      payload = %{
        "content_type" => "application/pdf",
        "file_size" => 1_048_576
      }

      conn = post(conn, ~p"/api/v1/storage/presign", payload)
      assert %{"data" => data} = json_response(conn, 200)

      assert data["allocated_region"] == "kollective-vault-eu-central"
      assert data["upload_url"] =~ "kollective-vault-eu-central"
    end
  end
end

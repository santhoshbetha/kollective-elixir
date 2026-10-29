defmodule KollectiveWeb.Admin.CryptoBackupControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.User

  setup %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "CryptoBackupController lifecycle" do
    test "store_backup saves encrypted backup and salt successfully", %{conn: conn, user: user} do
      payload = %{
        "backup" => %{
          "encrypted_private_key_backup" => "ENCRYPTED_BLOB_V1_KEYSTORE",
          "backup_salt" => "RANDOM_PBKDF2_SALT_XYZ"
        }
      }

      conn = post(conn, ~p"/api/v1/auth/backup_key", payload)
      assert json_response(conn, 200)["status"] == "success"

      updated_user = Repo.get!(User, user.id)
      assert updated_user.encrypted_private_key_backup == "ENCRYPTED_BLOB_V1_KEYSTORE"
      assert updated_user.backup_salt == "RANDOM_PBKDF2_SALT_XYZ"
    end

    test "store_backup accepts direct unnested parameters", %{conn: conn, user: user} do
      payload = %{
        "encrypted_private_key_backup" => "DIRECT_KEYSTORE_DATA",
        "backup_salt" => "DIRECT_SALT_123"
      }

      conn = post(conn, ~p"/api/v1/auth/backup_key", payload)
      assert json_response(conn, 200)["status"] == "success"

      updated_user = Repo.get!(User, user.id)
      assert updated_user.encrypted_private_key_backup == "DIRECT_KEYSTORE_DATA"
      assert updated_user.backup_salt == "DIRECT_SALT_123"
    end

    test "store_backup with invalid params returns 422", %{conn: conn} do
      payload = %{
        "backup" => %{
          "encrypted_private_key_backup" => nil,
          "backup_salt" => nil
        }
      }

      conn = post(conn, ~p"/api/v1/auth/backup_key", payload)
      assert response = json_response(conn, 422)
      assert response["error"] =~ "Failed to parse backup schemas"
    end

    test "fetch_backup returns backup data when registered", %{conn: conn, user: user} do
      # First store the backup
      user
      |> User.backup_changeset(%{
        "encrypted_private_key_backup" => "STORED_CIPHERTEXT",
        "backup_salt" => "SALT_ABC"
      })
      |> Repo.update!()

      conn = get(conn, ~p"/api/v1/auth/recover_key")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["encrypted_private_key_backup"] == "STORED_CIPHERTEXT"
      assert data["backup_salt"] == "SALT_ABC"
    end

    test "fetch_backup returns has_key: false when no backup is present", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/auth/recover_key")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["has_key"] == false
      assert data["has_backup"] == false
      assert data["encrypted_private_key_backup"] == nil
    end
  end
end

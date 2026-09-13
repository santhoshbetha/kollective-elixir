defmodule KollectiveWeb.ResetPasswordControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures
  import Ecto.Query

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User
  alias Kollective.Accounts.UserToken
  alias Kollective.Repo

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "POST /api/users/reset_password (request reset link)" do
    test "sends reset password instructions when email exists", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/users/reset_password", %{
          "user" => %{"email" => user.email}
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["message"] =~ "password reset link has been sent"

      # Verify token was created in the database
      assert Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
               )
             )
    end

    test "returns 200 even if email does not exist (prevents user enumeration)", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/reset_password", %{
          "user" => %{"email" => "nonexistent@example.com"}
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["message"] =~ "password reset link has been sent"
    end

    test "returns 403 when user is already authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Kollective.Accounts.Scope.for_user(user))
        |> post(~p"/api/users/reset_password", %{
          "user" => %{"email" => user.email}
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] =~ "already logged in"
    end
  end

  describe "PUT /api/users/reset_password/:token (submit new password)" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "resets password with valid token and password params", %{
      conn: conn,
      user: user,
      token: token
    } do
      new_password = "BrandNewValidPassword123!"

      conn =
        put(conn, ~p"/api/users/reset_password/#{token}", %{
          "user" => %{
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["message"] == "Password has been reset successfully"

      # Verify the updated password is valid for the user
      updated_user = Repo.get!(User, user.id)
      assert User.valid_password?(updated_user, new_password)

      # Verify the token cannot be reused
      retry_conn =
        put(build_conn(), ~p"/api/users/reset_password/#{token}", %{
          "user" => %{
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert retry_conn.status == 401
      retry_response = json_response(retry_conn, 401)
      assert retry_response["message"] =~ "invalid or has expired"
    end

    test "returns 422 when password validations fail", %{conn: conn, token: token} do
      conn =
        put(conn, ~p"/api/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "mismatch"
          }
        })

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["message"] == "Validation failed"
      assert response["errors"]["password"] || response["errors"]["password_confirmation"]
    end

    test "returns 401 when token is invalid", %{conn: conn} do
      conn =
        put(conn, ~p"/api/users/reset_password/invalid-token-string", %{
          "user" => %{
            "password" => "NewPassword123!",
            "password_confirmation" => "NewPassword123!"
          }
        })

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["status"] == "error"
      assert response["message"] =~ "invalid or has expired"
    end

    test "returns 401 when token has expired", %{conn: conn, token: token} do
      expire_token(token)

      conn =
        put(conn, ~p"/api/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "NewPassword123!",
            "password_confirmation" => "NewPassword123!"
          }
        })

      assert conn.status == 401
      response = json_response(conn, 401)
      assert response["status"] == "error"
      assert response["message"] =~ "invalid or has expired"
    end
  end

  defp expire_token(token) do
    {:ok, decoded_token} = Base.url_decode64(token, padding: false)
    hashed_token = :crypto.hash(:sha256, decoded_token)
    dt = DateTime.add(DateTime.utc_now(:second), -30, :day)

    Repo.update_all(
      from(ut in UserToken, where: ut.token == ^hashed_token),
      set: [inserted_at: dt]
    )
  end
end

defmodule KollectiveWeb.ConfirmationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures
  import Ecto.Query

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User
  alias Kollective.Accounts.UserToken
  alias Kollective.Repo

  describe "POST /api/users/resend_confirmation" do
    test "resends confirmation instructions for unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => user.email}
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["message"] == "Confirmation email sent successfully"

      assert Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
               )
             )
    end

    test "returns 409 conflict when user is already confirmed", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => user.email}
        })

      assert conn.status == 409
      response = json_response(conn, 409)
      assert response["status"] == "error"
      assert response["message"] == "Failed to resend confirmation email"
      assert "User already confirmed" in response["errors"]
    end

    test "returns 404 not found when email does not exist", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => "nonexistent@example.com"}
        })

      assert conn.status == 404
      response = json_response(conn, 404)
      assert response["status"] == "error"
      assert response["message"] == "User not found"
    end

    test "returns 403 when user is already authenticated", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> assign(:current_scope, Kollective.Accounts.Scope.for_user(user))
        |> post(~p"/api/users/resend_confirmation", %{
          "user" => %{"email" => user.email}
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] =~ "already logged in"
    end
  end

  describe "POST /api/users/confirm/:token" do
    setup do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms user with a valid token", %{conn: conn, user: user, token: token} do
      conn = post(conn, ~p"/api/users/confirm/#{token}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["message"] == "Email confirmed successfully"
      assert response["user"]["id"] == to_string(user.id)

      # Verify the user is marked confirmed in the database
      updated_user = Repo.get!(User, user.id)
      assert updated_user.confirmed_at != nil
      assert updated_user.is_confirmed == true

      # Verify the token cannot be reused
      retry_conn = post(build_conn(), ~p"/api/users/confirm/#{token}")
      assert retry_conn.status == 422
      retry_response = json_response(retry_conn, 422)
      assert retry_response["message"] =~ "invalid or has expired"
    end

    test "returns 422 when token is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/users/confirm/invalid-token-string")

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["message"] =~ "invalid or has expired"
    end

    test "returns 422 when token has expired", %{conn: conn, token: token} do
      expire_token(token)

      conn = post(conn, ~p"/api/users/confirm/#{token}")

      assert conn.status == 422
      response = json_response(conn, 422)
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

defmodule KollectiveWeb.RegistrationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures

  describe "POST /api/users/register - JSON API" do
    test "creates account with valid attributes", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/api/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      # 🔄 Align to expect the clean 201 header state
      assert conn.status == 201
      response = json_response(conn, 201)
      # 💡 Match your custom JSON layout nesting
      assert response["data"]["user"]["email"] == email
    end

    test "returns error for invalid email", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/register", %{
          "user" => %{"email" => "invalid-email"}
        })

      assert conn.status in [400, 422]
      response = json_response(conn, conn.status)
      assert response["error"] || response["errors"]
    end

    test "returns error when already authenticated", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> assign(:current_user, user)
        # ➕ Add this line to build the structural :current_scope metadata assign!
        |> KollectiveWeb.UserAuth.fetch_current_scope_for_user([])
        |> post(~p"/api/users/register", %{
          "user" => valid_user_attributes(email: unique_user_email())
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] =~ "already logged in"
    end
  end
end

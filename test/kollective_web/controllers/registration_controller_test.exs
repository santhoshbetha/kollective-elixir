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
      assert response["data"]["user"]["type"] == "citizen"

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.type == :citizen
    end

    test "creates account with organization type", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/api/users/register", %{
          "user" =>
            valid_user_attributes(email: email)
            |> Map.put("type", "organization")
            |> Map.put("Org name", "Acme Org")
        })

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["data"]["user"]["email"] == email
      assert response["data"]["user"]["type"] == "organization"

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.type == :organization
    end

    test "ignores unallowed types (scholar, journalist, activist) and defaults to citizen", %{
      conn: conn
    } do
      for unallowed <- ["scholar", "journalist", "activist", "other"] do
        email = unique_user_email()

        res_conn =
          post(conn, ~p"/api/users/register", %{
            "user" => Map.put(valid_user_attributes(email: email), "type", unallowed)
          })

        assert res_conn.status == 201
        response = json_response(res_conn, 201)
        assert response["data"]["user"]["type"] == "citizen"

        user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
        assert user.type == :citizen
      end
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

    test "creates organization account with 'Org name' and 'representative name'", %{
      conn: conn
    } do
      email = unique_user_email()

      attrs =
        valid_user_attributes(email: email)
        |> Map.put("type", "organization")
        |> Map.put("Org name", "Freedom Forum")
        |> Map.put("representative name", "Jane Doe")

      conn = post(conn, ~p"/api/users/register", %{"user" => attrs})

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["data"]["user"]["email"] == email
      assert response["data"]["user"]["type"] == "organization"
      assert response["data"]["user"]["display_name"] == "Freedom Forum"
      assert response["data"]["user"]["representative_name"] == "Jane Doe"

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.type == :organization
      assert user.display_name == "Freedom Forum"
      assert user.representative_name == "Jane Doe"
      assert user.birth_year == nil
      assert user.age == nil
    end

    test "creates organization without requiring birthday or date of birth", %{conn: conn} do
      email = unique_user_email()

      attrs =
        valid_user_attributes(email: email)
        |> Map.put("type", "organization")
        |> Map.put("Org name", "Tech Foundation")
        |> Map.drop(["birthday", "date_of_birth"])

      conn = post(conn, ~p"/api/users/register", %{"user" => attrs})

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["data"]["user"]["display_name"] == "Tech Foundation"

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.type == :organization
      assert user.birth_year == nil
      assert user.age == nil
    end

    test "creates organization account when representative name is omitted", %{conn: conn} do
      email = unique_user_email()

      attrs =
        valid_user_attributes(email: email)
        |> Map.put("type", "organization")
        |> Map.put("org_name", "Global Watch")

      conn = post(conn, ~p"/api/users/register", %{"user" => attrs})

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["data"]["user"]["display_name"] == "Global Watch"
      assert response["data"]["user"]["representative_name"] == nil

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.type == :organization
      assert user.display_name == "Global Watch"
      assert user.representative_name == nil
    end

    test "fails organization registration when org name is missing", %{conn: conn} do
      email = unique_user_email()

      attrs =
        valid_user_attributes(email: email)
        |> Map.put("type", "organization")
        |> Map.drop(["display_name", "displayname", "org_name", "org name", "Org name"])

      conn = post(conn, ~p"/api/users/register", %{"user" => attrs})

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["errors"]["display_name"] != nil
    end

    test "allows updating representative when someone takes over the org activity", %{
      conn: conn
    } do
      email = unique_user_email()

      attrs =
        valid_user_attributes(email: email)
        |> Map.put("type", "organization")
        |> Map.put("Org name", "Civic Org")
        |> Map.put("representative name", "Retiring Representative")

      res_conn = post(conn, ~p"/api/users/register", %{"user" => attrs})
      assert res_conn.status == 201

      user = Kollective.Repo.get_by!(Kollective.Accounts.User, email: email)
      assert user.representative_name == "Retiring Representative"

      auth_conn =
        conn
        |> authenticate_conn(user)
        |> KollectiveWeb.UserAuth.fetch_current_scope_for_user([])
        |> put(~p"/api/v1/profile", %{
          "user" => %{
            "representative name" => "New Successor Representative"
          }
        })

      assert auth_conn.status == 200
      update_response = json_response(auth_conn, 200)
      assert update_response["data"]["representative_name"] == "New Successor Representative"

      updated_user = Kollective.Repo.get!(Kollective.Accounts.User, user.id)
      assert updated_user.representative_name == "New Successor Representative"
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

defmodule KollectiveWeb.UserControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.Accounts

  @valid_attrs %{
    "email" => "user@example.com",
    "password" => "SuperSecretPassword123!",
    "displayname" => "Jane Doe",
    "username" => "janedoe",
    "birthday" => "1995-05-15",
    "country" => "US"
  }

  @invalid_attrs %{
    "email" => "bad-email",
    "password" => "short"
  }

  describe "register user (create action)" do
    test "renders user and token when data is valid (defaults type to citizen)", %{conn: conn} do
      conn = post(conn, ~p"/api/users", user: @valid_attrs)

      assert response = json_response(conn, 201)
      assert response["message"] =~ "Registration successful"
      assert response["data"]["token"] != nil
      assert response["data"]["user"]["email"] == "user@example.com"
      assert response["data"]["user"]["type"] == "citizen"

      user = Accounts.get_user_by_email("user@example.com")
      assert user.type == :citizen
    end

    test "registers user with organization type when type is organization", %{conn: conn} do
      org_attrs =
        Map.merge(@valid_attrs, %{
          "email" => "org@example.com",
          "username" => "grassroots_org",
          "type" => "organization"
        })

      conn = post(conn, ~p"/api/users", user: org_attrs)

      assert response = json_response(conn, 201)
      assert response["data"]["user"]["email"] == "org@example.com"
      assert response["data"]["user"]["type"] == "organization"

      user = Accounts.get_user_by_email("org@example.com")
      assert user.type == :organization
    end

    test "ignores unallowed registration types like scholar, journalist, activist and defaults to citizen",
         %{conn: conn} do
      for {unallowed_type, idx} <-
            Enum.with_index(["scholar", "journalist", "activist", "custom_type"]) do
        email = "unallowed#{idx}@example.com"

        payload =
          Map.merge(@valid_attrs, %{
            "email" => email,
            "username" => "user#{idx}",
            "type" => unallowed_type
          })

        res_conn = post(conn, ~p"/api/users", user: payload)
        assert response = json_response(res_conn, 201)
        assert response["data"]["user"]["type"] == "citizen"

        user = Accounts.get_user_by_email(email)
        assert user.type == :citizen
      end
    end

    test "renders validation errors when database registration fails", %{conn: conn} do
      conn = post(conn, ~p"/api/users", user: @invalid_attrs)

      assert errors = json_response(conn, 422)["errors"]
      # Asserts that Ecto validation messaging caught the bad fields
      assert errors["email"] != nil
    end

    test "creates organization user with 'Org name' and 'representative name' without birthday",
         %{conn: conn} do
      email = "org_user_test@example.com"

      payload =
        @valid_attrs
        |> Map.drop(["displayname", "display_name", "birthday", "date_of_birth"])
        |> Map.put("email", email)
        |> Map.put("username", "orguser1")
        |> Map.put("type", "organization")
        |> Map.put("Org name", "Community League")
        |> Map.put("representative name", "Carlos Santana")

      conn = post(conn, ~p"/api/users", user: payload)
      assert response = json_response(conn, 201)
      assert response["data"]["user"]["type"] == "organization"
      assert response["data"]["user"]["display_name"] == "Community League"
      assert response["data"]["user"]["representative_name"] == "Carlos Santana"

      user = Accounts.get_user_by_email(email)
      assert user.type == :organization
      assert user.display_name == "Community League"
      assert user.representative_name == "Carlos Santana"
      assert user.birth_year == nil
      assert user.age == nil
    end

    test "fails organization registration when org name is missing", %{conn: conn} do
      email = "org_missing_name@example.com"

      payload =
        @valid_attrs
        |> Map.drop(["display_name", "displayname", "org_name", "org name", "Org name"])
        |> Map.put("email", email)
        |> Map.put("username", "orgnoname")
        |> Map.put("type", "organization")

      conn = post(conn, ~p"/api/users", user: payload)
      assert errors = json_response(conn, 422)["errors"]
      assert errors["display_name"] != nil
    end

    test "strips out unallowed parameters aggressively", %{conn: conn} do
      malicious_payload = Map.put(@valid_attrs, "is_admin", true)

      conn = post(conn, ~p"/api/users", user: malicious_payload)
      assert json_response(conn, 201)

      # Verifies the user inside the DB context did not receive the "is_admin" flag
      assert Accounts.get_user_by_email("user@example.com").is_admin == false
    end
  end
end

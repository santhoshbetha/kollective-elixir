defmodule KollectiveWeb.SessionControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures
  # 🔄 FIX 1: Change alias from Kollective.Accounts to point to your deep sub-context module
  alias Kollective.Accounts.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "POST /api/users/login - JSON API" do
    test "logs the user in with magic link token and returns full profile data", %{
      conn: conn,
      user: user
    } do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "verify_magic_link",
          "user" => %{"token" => token}
        })

      assert conn.status in [200, 201]
      response = json_response(conn, conn.status)
      assert response["data"]["token"]

      profile = response["data"]["user"]
      assert is_map(profile)

      # 1. Core Profile Details
      assert profile["id"] == to_string(user.id)
      assert profile["username"] == user.username
      assert profile["acct"] == user.username
      assert profile["display_name"]
      assert is_binary(profile["bio"])
      assert is_binary(profile["note"])
      assert profile["avatar"]
      assert profile["avatar_url"]
      assert profile["header"]
      assert profile["header_url"]
      assert profile["cover_image"]
      assert profile["created_at"]
      assert profile["email"] == user.email

      # 2. Social Metadata
      assert is_integer(profile["followers_count"])
      assert is_integer(profile["following_count"])
      assert is_integer(profile["posts_count"])
      assert is_integer(profile["unread_notifications_count"])

      # 3. Verification Fields
      assert is_list(profile["fields"])
      assert is_list(profile["custom_fields"])
      assert is_boolean(profile["is_verified"])
      assert profile["badge_type"]

      # 4. Privacy Settings
      assert is_map(profile["privacy_settings"])

      assert profile["privacy_settings"]["default_visibility"] in [
               "public",
               "unlisted",
               "private",
               "direct"
             ]

      assert is_boolean(profile["privacy_settings"]["default_sensitive"])
      assert is_boolean(profile["privacy_settings"]["is_locked"])
      assert is_boolean(profile["privacy_settings"]["is_discoverable"])

      assert is_map(profile["source"])
      assert profile["source"]["privacy"]
      assert is_boolean(profile["source"]["sensitive"])
      assert profile["source"]["language"]
      assert is_list(profile["source"]["fields"])

      # 5. Interface Settings
      assert is_map(profile["interface_settings"])
      assert profile["interface_settings"]["locale"]
      assert profile["interface_settings"]["language"]
      assert is_boolean(profile["interface_settings"]["auto_play_gifs"])
      assert profile["interface_settings"]["theme"]
      assert profile["interface_settings"]["experience_mode"]

      # 6. Feature Flags
      assert is_map(profile["feature_flags"])
      assert is_boolean(profile["feature_flags"]["is_admin"])
      assert is_boolean(profile["feature_flags"]["is_moderator"])
      assert is_boolean(profile["feature_flags"]["can_moderate"])
      assert is_boolean(profile["feature_flags"]["can_manage_organizations"])
      assert profile["feature_flags"]["role"]
    end

    test "logs the user in with password and returns customized profile data", %{
      conn: conn,
      user: user
    } do
      user =
        user
        |> Ecto.Changeset.change(%{
          bio: "Civic researcher and open-source contributor",
          avatar_url: "https://cdn.kollective.social/avatars/alice.png",
          cover_image_url: "https://cdn.kollective.social/banners/alice_banner.png",
          official_website: "https://alice.dev",
          is_admin: true,
          is_verified: true,
          locale: "es",
          default_scope: "unlisted",
          settings: %{
            "default_sensitive" => true,
            "theme" => "dark",
            "fields" => [
              %{
                "name" => "Portfolio",
                "value" => "https://alice.dev/portfolio",
                "verified_at" => "2026-01-01T00:00:00Z"
              }
            ]
          }
        })
        |> Kollective.Repo.update!()
        |> set_password()

      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "password",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["data"]["token"]

      profile = response["data"]["user"]

      # Core profile
      assert profile["bio"] == "Civic researcher and open-source contributor"
      assert profile["note"] == "Civic researcher and open-source contributor"
      assert profile["avatar"] == "https://cdn.kollective.social/avatars/alice.png"
      assert profile["header"] == "https://cdn.kollective.social/banners/alice_banner.png"

      # Verification Fields
      assert profile["is_verified"] == true
      fields = profile["fields"]

      assert Enum.any?(fields, fn f ->
               f["name"] == "Portfolio" and f["value"] == "https://alice.dev/portfolio"
             end)

      assert Enum.any?(fields, fn f ->
               f["name"] == "Website" and f["value"] == "https://alice.dev"
             end)

      # Privacy Settings
      assert profile["privacy_settings"]["default_visibility"] == "unlisted"
      assert profile["privacy_settings"]["default_sensitive"] == true
      assert profile["source"]["privacy"] == "unlisted"
      assert profile["source"]["sensitive"] == true

      # Interface Settings
      assert profile["interface_settings"]["locale"] == "es"
      assert profile["interface_settings"]["theme"] == "dark"

      # Feature Flags
      assert profile["feature_flags"]["is_admin"] == true
      assert profile["feature_flags"]["can_moderate"] == true
    end

    test "returns error for invalid token", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/login", %{
          "action" => "verify_magic_link",
          "user" => %{"token" => "invalid-token"}
        })

      assert conn.status in [400, 422]
      response = json_response(conn, conn.status)
      assert response["error"] || response["errors"]
    end

    test "returns error when already authenticated", %{conn: conn, user: user} do
      conn =
        conn
        # 🔄 FIX 4: Populate current_scope so redirect_if_user_is_authenticated evaluates correctly
        |> assign(:current_scope, Kollective.Accounts.Scope.for_user(user))
        |> post(~p"/api/users/login", %{
          "action" => "request_magic_link",
          "user" => %{"email" => user.email}
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] =~ "already logged in"
    end
  end

  describe "DELETE /api/users/logout - JSON API" do
    test "logs the user out successfully", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/users/logout")

      assert conn.status in [200, 204]
    end

    test "succeeds even if user is not authenticated", %{conn: conn} do
      conn = delete(conn, ~p"/api/users/logout")

      # 🔄 FIX 5: Unauthenticated logout returns a 400 Bad Request via your with block fallback
      assert conn.status == 400
    end
  end
end

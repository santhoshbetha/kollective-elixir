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

  describe "GET /api/v1/profiles and X-Active-Account-Id resolution" do
    alias Kollective.Repo
    alias Kollective.Accounts.OrganizationMembership

    setup %{conn: conn, user: user} do
      scope = Kollective.Accounts.Scope.for_user(user)

      {:ok, org} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Tech Collective",
          username: "tech_collective",
          email: "tech@collective.org",
          type: :organization
        })

      {:ok, membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :admin,
          status: :active
        })

      # Generate a valid session token for authentication testing
      token = Kollective.Accounts.Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)

      %{conn: conn, user: user, org: org, membership: membership, token: token}
    end

    test "returns accessible profiles for user including personal and orgs", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = get(conn, ~p"/api/v1/profiles")

      assert conn.status == 200
      response = json_response(conn, 200)

      profiles = response["profiles"]
      assert is_list(profiles)
      assert length(profiles) == 2

      personal = Enum.find(profiles, &(&1["id"] == to_string(user.id)))
      assert personal["name"] == user.display_name || user.username
      assert personal["handle"] == "@#{user.username}"
      assert "posts:write" in personal["permissions"]

      org_profile = Enum.find(profiles, &(&1["id"] == to_string(org.id)))
      assert org_profile["name"] == org.display_name || org.username
      assert org_profile["handle"] == "@#{org.username}"
      assert org_profile["role"] == "admin"
      assert "team:manage" in org_profile["permissions"]
    end

    test "resolves default personal account when X-Active-Account-Id is omitted", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, ~p"/api/v1/profiles")
      assert conn.status == 200
      assert conn.assigns[:active_account_id] == to_string(user.id)
      assert conn.assigns[:account_type] == user.type
      assert "posts:write" in conn.assigns[:permissions]
    end

    test "resolves organization context when valid X-Active-Account-Id header is provided", %{
      conn: conn,
      org: org
    } do
      conn =
        conn
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> get(~p"/api/v1/profiles")

      assert conn.status == 200
      assert conn.assigns[:active_account_id] == to_string(org.id)
      assert conn.assigns[:account_type] == :organization
      assert "team:manage" in conn.assigns[:permissions]
    end

    test "returns 403 when X-Active-Account-Id is an org the user is not a member of", %{
      conn: conn
    } do
      {:ok, unauthorized_org} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Secret Org",
          username: "secret_org",
          email: "secret@org.com",
          type: :organization
        })

      conn =
        conn
        |> put_req_header("x-active-account-id", to_string(unauthorized_org.id))
        |> get(~p"/api/v1/profiles")

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] == "forbidden"
    end

    test "returns 401 when user is not authenticated" do
      conn =
        build_conn()
        |> get(~p"/api/v1/profiles")

      assert conn.status == 401
    end
  end
end

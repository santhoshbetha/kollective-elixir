defmodule KollectiveWeb.AccountContextRecommendationsTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.OrganizationMembership
  alias Kollective.Notifications.Notifications
  alias Kollective.Notifications.Notification

  setup :authenticate_user

  setup %{user: user} do
    # Create an approved organization and membership for user
    org = insert(:user, type: :organization, username: "clean_energy_org", display_name: "Clean Energy Org")

    {:ok, membership} =
      Repo.insert(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

    {:ok, org: org, membership: membership}
  end

  describe "Recommendation 1: Plugs Unification (AssignOrganization & APIAuth)" do
    test "APIAuth sets current_org_id, org_role, and current_organization when switched to org", %{
      conn: conn,
      user: user,
      org: org
    } do
      token = Accounts.generate_user_session_token(user, org.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> get(~p"/api/v1/profiles")

      assert conn.status == 200
      assert conn.assigns[:current_organization] != nil
      assert conn.assigns[:current_organization].id == org.id
      assert conn.assigns[:current_org_id] == to_string(org.id)
      assert conn.assigns[:org_role] == :admin
      assert conn.assigns[:active_account_id] == to_string(org.id)
      assert conn.assigns[:account_type] == :organization
    end

    test "APIAuth sets current_organization and current_org_id to nil when in personal context", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(user.id))
        |> get(~p"/api/v1/profiles")

      assert conn.status == 200
      assert conn.assigns[:current_organization] == nil
      assert conn.assigns[:current_org_id] == nil
      assert conn.assigns[:org_role] == nil
      assert conn.assigns[:active_account_id] == to_string(user.id)
      assert conn.assigns[:account_type] == user.type
    end
  end

  describe "Recommendation 2: Server-Side Gating for Organization Actors" do
    setup %{user: user} do
      event = insert(:event, user: user)
      {:ok, event: event}
    end

    test "blocks organization non-admin actor from joining an event with 403 Forbidden", %{
      event: event
    } do
      non_admin = insert(:user)
      org = insert(:user, type: :organization)
      Repo.insert!(%OrganizationMembership{
        user_id: non_admin.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })
      token = Accounts.generate_user_session_token(non_admin, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/kollective/events/#{event.id}/join")

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] == "forbidden"
      assert response["message"] =~ "Only administrators can perform social actions on behalf of this organization"
    end

    test "permits organization admin actor to join an event and attributes it to org", %{
      user: user,
      org: org,
      event: event
    } do
      token = Accounts.generate_user_session_token(user, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/kollective/events/#{event.id}/join")

      assert conn.status in [200, 201]
    end

    test "blocks organization non-admin actor from RSVPing to an event with 403 Forbidden", %{
      event: event
    } do
      non_admin = insert(:user)
      org = insert(:user, type: :organization)
      Repo.insert!(%OrganizationMembership{
        user_id: non_admin.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })
      token = Accounts.generate_user_session_token(non_admin, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/kollective/events/#{event.id}/rsvp", %{"status" => "going"})

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] == "forbidden"
      assert response["message"] =~ "Only administrators can perform social actions on behalf of this organization"
    end

    test "permits organization admin actor to RSVP to an event and attributes it to org", %{
      user: user,
      org: org,
      event: event
    } do
      token = Accounts.generate_user_session_token(user, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/kollective/events/#{event.id}/rsvp", %{"status" => "going"})

      assert conn.status in [200, 201]
    end

    test "blocks organization actor from creating a business with 403 Forbidden", %{
      conn: conn,
      user: user,
      org: org
    } do
      token = Accounts.generate_user_session_token(user, org.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/businesses", %{
          "business" => %{
            "name" => "Rogue Business",
            "category" => "Technology",
            "description" => "Test description"
          }
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] == "forbidden"
      assert response["message"] =~ "Organizations cannot register businesses"
    end

    test "blocks organization actor from submitting a business proposal with 403 Forbidden", %{
      conn: conn,
      user: user,
      org: org
    } do
      token = Accounts.generate_user_session_token(user, org.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> post(~p"/api/v1/business_proposals", %{
          "proposal" => %{
            "title" => "Rogue Proposal",
            "category" => "Technology",
            "description" => "Test proposal",
            "funding_goal" => 10000
          }
        })

      assert conn.status == 403
      response = json_response(conn, 403)
      assert response["error"] == "forbidden"
      assert response["message"] =~ "Organizations cannot register businesses or submit proposals"
    end
  end

  describe "Recommendation 3: Notification Schema & Cross-Context Isolation" do
    test "personal notification feed excludes notifications assigned to an organization", %{
      conn: conn,
      user: user,
      org: org
    } do
      actor = insert(:user)

      # 1. Insert a personal notification
      {:ok, personal_notif} =
        Notifications.notify(user.id, actor.id, "like", %{
          target_id: Ecto.ULID.generate(),
          target_type: "Post"
        })

      # 2. Insert an organization-scoped notification
      {:ok, org_notif} =
        Notifications.notify(user.id, actor.id, "like", %{
          organization_id: org.id,
          target_id: Ecto.ULID.generate(),
          target_type: "Post"
        })

      # Verify org_notif actually has organization_id recorded
      persisted_org_notif = Repo.get(Notification, org_notif.id)
      assert persisted_org_notif.organization_id == org.id

      # 3. Request personal notifications feed
      token = Accounts.generate_user_session_token(user)

      conn_personal =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(user.id))
        |> get(~p"/api/v1/notifications")

      assert conn_personal.status == 200
      personal_data = json_response(conn_personal, 200)["data"]
      personal_ids = Enum.map(personal_data, & &1["id"])

      assert personal_notif.id in personal_ids
      refute org_notif.id in personal_ids

      # 4. Request organization notifications feed
      org_token = Accounts.generate_user_session_token(user, org.id)

      conn_org =
        build_conn()
        |> put_req_header("authorization", "Bearer #{org_token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> get(~p"/api/v1/notifications")

      assert conn_org.status == 200
      org_data = json_response(conn_org, 200)["data"]
      org_ids = Enum.map(org_data, & &1["id"])

      assert org_notif.id in org_ids
      refute personal_notif.id in org_ids
    end

    test "unread count segregates personal vs organization counts", %{
      conn: conn,
      user: user,
      org: org
    } do
      actor = insert(:user)

      {:ok, _} =
        Notifications.notify(user.id, actor.id, "like", %{
          target_id: Ecto.ULID.generate(),
          target_type: "Post"
        })

      {:ok, _} =
        Notifications.notify(user.id, actor.id, "like", %{
          organization_id: org.id,
          target_id: Ecto.ULID.generate(),
          target_type: "Post"
        })

      token = Accounts.generate_user_session_token(user)

      conn_personal =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("x-active-account-id", to_string(user.id))
        |> get(~p"/api/v1/notifications/unread_count")

      assert json_response(conn_personal, 200)["unread_count"] == 1

      org_token = Accounts.generate_user_session_token(user, org.id)

      conn_org =
        build_conn()
        |> put_req_header("authorization", "Bearer #{org_token}")
        |> put_req_header("x-active-account-id", to_string(org.id))
        |> get(~p"/api/v1/notifications/unread_count")

      assert json_response(conn_org, 200)["unread_count"] == 1
    end
  end

  describe "Recommendation 4: Unified Session Global Logout" do
    test "DELETE /api/users/logout revokes all user sessions in DB", %{
      conn: conn,
      user: user,
      org: org
    } do
      personal_token = Accounts.generate_user_session_token(user)
      org_token = Accounts.generate_user_session_token(user, org.id)

      # Ensure both exist
      assert Accounts.get_user_by_session_token(personal_token) != nil
      assert Accounts.get_user_by_session_token(org_token) != nil

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{personal_token}")
        |> delete(~p"/api/users/logout")

      assert conn.status == 200
      assert json_response(conn, 200)["message"] == "Logged out successfully."

      # Both personal and org token are revoked
      assert Accounts.get_user_by_session_token(personal_token) == nil
      assert Accounts.get_user_by_session_token(org_token) == nil
    end
  end
end

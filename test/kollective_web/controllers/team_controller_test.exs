# test/kollective_web/controllers/team_controller_test.exs
defmodule KollectiveWeb.TeamControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo

  setup %{conn: conn} do
    # 1. Create a user (Author/Member)
    {:ok, user} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "Charlie Roster",
        username: "charlie_codes",
        email: "charlie@test.com"
      })

    # 2. Create an Organization
    {:ok, org} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "Dev Collective",
        username: "devco",
        email: "devco@test.com",
        type: :organization
      })

    # 3. Create a valid active membership
    {:ok, _membership} =
      Repo.insert(%Kollective.Accounts.OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :contributor,
        status: :active
      })

    # 4. Authenticate the connection natively
    scope = Kollective.Accounts.Scope.for_user(user)

    conn =
      conn
      |> assign(:current_user, user)
      |> assign(:current_scope, scope)

    %{conn: conn, user: user, org: org}
  end

  describe "GET /api/v1/org-settings/members - Requiring Active Organization Guard" do
    test "returns 200 OK and lists members when a valid X-Organization-Id header is passed", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> get(~p"/api/v1/org-settings/members")

      # Extract response wrapper matching our TeamJSON rendering format
      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) == 1

      [member_data] = response["data"]
      assert member_data["role"] == "contributor"
      assert member_data["status"] == "active"
      assert member_data["user"]["id"] == user.id
      assert member_data["user"]["username"] == "charlie_codes"
    end

    test "returns 400 Bad Request and halts when the X-Organization-Id header is completely missing",
         %{conn: conn} do
      # Make the request without putting the required custom header
      conn = get(conn, ~p"/api/v1/org-settings/members")

      # Assert that the RequireActiveOrganization plug intercepted and rejected it
      response = json_response(conn, 400)

      assert response["error"] ==
               "This action requires an active organization context. Please provide a valid X-Organization-Id header."
    end

    test "returns 403 Forbidden when the user is not an active member of the organization", %{
      conn: conn
    } do
      {:ok, other_org} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Other Org",
          username: "otherorg",
          email: "otherorg@test.com",
          type: :organization
        })

      conn =
        conn
        |> put_req_header("x-organization-id", to_string(other_org.id))
        |> get(~p"/api/v1/org-settings/members")

      assert json_response(conn, 403)["error"] =~ "not a member"
    end
  end

  describe "DELETE /api/v1/org-settings/members/:user_id" do
    test "successfully removes a contributor", %{conn: conn, org: org} do
      # Make the acting user an admin so they can manage the team
      {:ok, target_user} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Target Contributor",
          username: "target_contrib",
          email: "target@test.com"
        })

      {:ok, _membership} =
        Repo.insert(%Kollective.Accounts.OrganizationMembership{
          user_id: target_user.id,
          organization_id: org.id,
          role: :contributor,
          status: :active
        })

      conn =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> delete(~p"/api/v1/org-settings/members/#{target_user.id}")

      assert response(conn, 204)

      assert Repo.get_by(Kollective.Accounts.OrganizationMembership,
               user_id: target_user.id,
               organization_id: org.id
             ) == nil
    end

    test "returns 400 Bad Request when attempting to remove an owner", %{conn: conn, org: org} do
      {:ok, owner_user} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Org Owner",
          username: "org_owner",
          email: "owner@test.com"
        })

      {:ok, _membership} =
        Repo.insert(%Kollective.Accounts.OrganizationMembership{
          user_id: owner_user.id,
          organization_id: org.id,
          role: :owner,
          status: :active
        })

      conn =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> delete(~p"/api/v1/org-settings/members/#{owner_user.id}")

      assert json_response(conn, 400)["error"] =~ "transfer brand ownership"
    end
  end

  describe "GET /api/v1/org-settings/pending-invites" do
    setup do
      {:ok, invitee} =
        Repo.insert(%Kollective.Accounts.User{
          display_name: "Bob Guest",
          username: "bob_guest",
          email: "bob_guest@test.com"
        })

      %{invitee: invitee}
    end

    test "returns 200 OK and lists outstanding invitations safely", %{
      conn: conn,
      invitee: invitee,
      org: org
    } do
      # 1. Generate an outstanding invitation slot mapping
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: invitee.id,
        organization_id: org.id,
        role: :contributor,
        status: :pending
      })

      # 2. Perform the header-wrapped HTTP request simulation
      conn =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> get(~p"/api/v1/org-settings/pending-invites")

      # 3. Assert on output payload architecture constraints
      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) == 1

      [invite_payload] = response["data"]
      assert invite_payload["status"] == "pending"
      assert invite_payload["role"] == "contributor"
      assert invite_payload["user"]["username"] == "bob_guest"
    end

    test "returns an empty list when all invites are already accepted or processed", %{
      conn: conn,
      invitee: invitee,
      org: org
    } do
      # If the invitation status is active rather than pending, it must be hidden
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: invitee.id,
        organization_id: org.id,
        role: :contributor,
        status: :active
      })

      conn =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> get(~p"/api/v1/org-settings/pending-invites")

      response = json_response(conn, 200)
      assert response["data"] == []
    end
  end
end

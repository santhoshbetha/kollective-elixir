defmodule KollectiveWeb.OrganizationTeamInvitationTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.{OrganizationMembership, Organizations}

  import Kollective.AccountsFixtures

  setup :authenticate_user

  setup %{user: user} do
    org = user_fixture(%{type: :organization, display_name: "Acme Corp"})
    %{org: org, user: user}
  end

  describe "InvitationController (Scope 1: Personal User Account Operations)" do
    test "GET /api/invitations and /api/v1/invitations lists pending invites", %{
      conn: conn,
      user: user,
      org: org
    } do
      {:ok, membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :contributor,
          status: :pending
        })

      for path <- ["/api/v1/invitations", "/api/v1/invitations"] do
        res =
          conn
          |> get(path)
          |> json_response(200)

        assert is_list(res["data"])
        assert Enum.any?(res["data"], fn item -> item["id"] == to_string(membership.id) end)
      end
    end

    test "POST /api/invitations/:id/accept accepts invitation", %{
      conn: conn,
      user: user,
      org: org
    } do
      {:ok, membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :contributor,
          status: :pending
        })

      res =
        conn
        |> post("/api/v1/invitations/#{membership.id}/accept")
        |> json_response(200)

      assert res["data"]["status"] == "approved"

      updated = Repo.get(OrganizationMembership, membership.id)
      assert updated.status == :approved
    end

    test "POST /api/v1/invitations/:id/decline declines invitation", %{
      conn: conn,
      user: user,
      org: org
    } do
      {:ok, membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :contributor,
          status: :pending
        })

      conn
      |> post("/api/v1/invitations/#{membership.id}/decline")
      |> json_response(200)

      assert Repo.get(OrganizationMembership, membership.id) == nil
    end
  end

  describe "TeamController (Scope 2: General Team & Roster Operations)" do
    test "GET /api/v1/org-settings/members without X-Organization-Id returns 400", %{conn: conn} do
      conn
      |> get("/api/v1/org-settings/members")
      |> json_response(400)
    end

    test "GET /api/v1/org-settings/members returns 403 if user is not member of org", %{
      conn: conn,
      org: org
    } do
      conn
      |> put_req_header("x-organization-id", to_string(org.id))
      |> get("/api/v1/org-settings/members")
      |> json_response(403)
    end

    test "GET /api/v1/org-settings/members returns active roster for approved member", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

      other_user = user_fixture(%{display_name: "Team Mate"})

      Repo.insert!(%OrganizationMembership{
        user_id: other_user.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })

      res =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> get("/api/v1/org-settings/members")
        |> json_response(200)

      assert is_list(res["data"])
      assert length(res["data"]) >= 2
    end

    test "DELETE /api/v1/org-settings/members/:user_id removes member", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

      other_user = user_fixture()

      Repo.insert!(%OrganizationMembership{
        user_id: other_user.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })

      conn
      |> put_req_header("x-organization-id", to_string(org.id))
      |> delete("/api/v1/org-settings/members/#{other_user.id}")
      |> response(204)

      assert Repo.get_by(OrganizationMembership, organization_id: org.id, user_id: other_user.id) ==
               nil
    end

    test "DELETE /api/v1/org-settings/members/:user_id cannot remove owner", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :owner,
        status: :approved
      })

      conn
      |> put_req_header("x-organization-id", to_string(org.id))
      |> delete("/api/v1/org-settings/members/#{user.id}")
      |> json_response(400)
    end
  end

  describe "OrganizationController (Scope 3: /api/v1/org-admin Operations)" do
    test "POST /api/v1/org-admin/organizations/:org_id/invite fails 403 for contributor", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })

      invitee = user_fixture()

      conn
      |> put_req_header("x-organization-id", to_string(org.id))
      |> post("/api/v1/org-admin/organizations/#{org.id}/invite", %{
        "email" => invitee.email,
        "role" => "contributor"
      })
      |> json_response(403)
    end

    test "POST /api/v1/org-admin/organizations/:org_id/invite succeeds for admin", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

      invitee = user_fixture()

      res =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> post("/api/v1/org-admin/organizations/#{org.id}/invite", %{
          "email" => invitee.email,
          "role" => "contributor"
        })
        |> json_response(200)

      assert res["status"] == "success"
    end

    test "POST /api/v1/org-admin/transfer-ownership succeeds for owner", %{
      conn: conn,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :owner,
        status: :approved
      })

      new_owner = user_fixture()

      Repo.insert!(%OrganizationMembership{
        user_id: new_owner.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

      res =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> post("/api/v1/org-admin/transfer-ownership", %{
          "new_owner_id" => new_owner.id
        })
        |> json_response(200)

      assert res["status"] == "success"

      # Verify old owner demoted to admin and new owner promoted to owner
      old_owner_m = Organizations.get_organization_membership_by_user(user.id, org.id)
      new_owner_m = Organizations.get_organization_membership_by_user(new_owner.id, org.id)
      assert old_owner_m.role == :admin
      assert new_owner_m.role == :owner
    end
  end
end

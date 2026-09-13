defmodule KollectiveWeb.OrganizationAdminControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.{OrganizationMembership, Organizations}
  import Kollective.AccountsFixtures

  setup :authenticate_user

  setup %{user: admin} do
    org = user_fixture(%{type: :organization, display_name: "Action Org"})

    Repo.insert!(%OrganizationMembership{
      user_id: admin.id,
      organization_id: org.id,
      role: :admin,
      status: :approved
    })

    %{org: org, admin: admin}
  end

  describe "GET /api/v1/organizations/:org_id/requests" do
    test "lists pending members for admin", %{conn: conn, org: org} do
      applicant = user_fixture(%{username: "applicant_jane"})

      Repo.insert!(%OrganizationMembership{
        user_id: applicant.id,
        organization_id: org.id,
        role: :contributor,
        status: :pending
      })

      res =
        conn
        |> get("/api/v1/organizations/#{org.id}/requests")
        |> json_response(200)

      assert res["status"] == "success"
      assert is_list(res["data"])
      assert length(res["data"]) >= 1

      first = hd(res["data"])
      assert first["user"]["username"] == "applicant_jane"
      assert first["role"] == "contributor"
    end

    test "fails with 403 when user is not admin", %{org: org} do
      other_user = user_fixture()
      other_conn = authenticate_conn(build_conn(), other_user)

      res =
        other_conn
        |> get("/api/v1/organizations/#{org.id}/requests")
        |> json_response(403)

      assert res["error"] == "unauthorized"
    end
  end

  describe "POST /api/v1/organizations/:org_id/members/:user_id/role" do
    test "updates role successfully", %{conn: conn, org: org} do
      member = user_fixture()

      Repo.insert!(%OrganizationMembership{
        user_id: member.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })

      res =
        conn
        |> post("/api/v1/organizations/#{org.id}/members/#{member.id}/role", %{
          "new_role" => "admin"
        })
        |> json_response(200)

      assert res["status"] == "success"
      assert res["message"] == "Role updated successfully."

      updated = Organizations.get_organization_membership_by_user(member.id, org.id)
      assert updated.role == :admin
    end

    test "fails 400 when invalid role provided", %{conn: conn, org: org} do
      member = user_fixture()

      conn
      |> post("/api/v1/organizations/#{org.id}/members/#{member.id}/role", %{
        "new_role" => "super_admin"
      })
      |> json_response(400)
    end
  end

  describe "POST /api/v1/organization_requests/:membership_id/process" do
    test "processes join request approval", %{conn: conn, org: org} do
      applicant = user_fixture()

      membership =
        Repo.insert!(%OrganizationMembership{
          user_id: applicant.id,
          organization_id: org.id,
          role: :contributor,
          status: :pending
        })

      res =
        conn
        |> post("/api/v1/organization_requests/#{membership.id}/process", %{
          "status" => "approved"
        })
        |> json_response(200)

      assert res["status"] == "success"
      assert res["message"] == "Membership request successfully processed."

      updated = Repo.get(OrganizationMembership, membership.id)
      assert updated.status == :approved
    end
  end
end

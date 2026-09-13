# test/my_app_web/controllers/organization_controller_test.exs
defmodule KollectiveWeb.OrganizationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.OrganizationMembership

  setup %{conn: conn} do
    # 1. Create a true Owner
    {:ok, owner} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "True Owner",
        username: "boss",
        email: "owner@test.com"
      })

    # 2. Create a standard Administrator
    {:ok, admin_user} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "Admin Joe",
        username: "joe_admin",
        email: "joe@test.com"
      })

    # 3. Create a target scapegoat Contributor (Who the admin tries to promote to owner)
    {:ok, contributor} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "Contributor Cam",
        username: "cam_write",
        email: "cam@test.com"
      })

    # 4. Create the target Organization profile
    {:ok, org} =
      Repo.insert(%Kollective.Accounts.User{
        display_name: "Enterprise Inc",
        username: "enterprise",
        email: "enterprise@test.com",
        type: :organization
      })

    # 5. Connect roles inside memberships join mappings
    Repo.insert!(%OrganizationMembership{
      user_id: owner.id,
      organization_id: org.id,
      role: :owner,
      status: :active
    })

    Repo.insert!(%OrganizationMembership{
      user_id: admin_user.id,
      organization_id: org.id,
      role: :admin,
      status: :active
    })

    Repo.insert!(%OrganizationMembership{
      user_id: contributor.id,
      organization_id: org.id,
      role: :contributor,
      status: :active
    })

    %{conn: conn, owner: owner, admin: admin_user, contributor: contributor, org: org}
  end

  describe "POST /api/org-admin/transfer-ownership - Access Control Enforcements" do
    test "allows the true owner to successfully transfer organizational power", %{
      conn: conn,
      owner: owner,
      contributor: contributor,
      org: org
    } do
      payload = %{"new_owner_id" => contributor.id}

      conn =
        conn
        |> assign(:current_user, owner)
        |> put_req_header("x-organization-id", to_string(org.id))
        |> post(~p"/api/v1/org-admin/transfer-ownership", payload)

      assert json_response(conn, 200)["message"] == "Ownership transferred successfully."

      # Verify database structural updates reflect demotions/promotions correctly
      assert to_string(
               Repo.get_by(OrganizationMembership, user_id: owner.id, organization_id: org.id).role
             ) ==
               "admin"

      assert to_string(
               Repo.get_by(OrganizationMembership,
                 user_id: contributor.id,
                 organization_id: org.id
               ).role
             ) ==
               "owner"
    end

    test "explicitly blocks a standard Admin from transferring absolute ownership weights", %{
      conn: conn,
      admin: admin,
      contributor: contributor,
      org: org
    } do
      payload = %{"new_owner_id" => contributor.id}

      # Run the exact same HTTP request, but authenticate it as the Admin actor
      conn =
        conn
        |> assign(:current_user, admin)
        |> put_req_header("x-organization-id", to_string(org.id))
        |> post(~p"/api/v1/org-admin/transfer-ownership", payload)

      # Assert security layer blocked the action safely
      response = json_response(conn, 403)

      assert response["error"] ==
               "Absolute ownership credentials required to execute this operation."

      # Confirm database state was completely preserved from malicious modification
      assert to_string(
               Repo.get_by(OrganizationMembership, user_id: admin.id, organization_id: org.id).role
             ) ==
               "admin"

      assert to_string(
               Repo.get_by(OrganizationMembership,
                 user_id: contributor.id,
                 organization_id: org.id
               ).role
             ) ==
               "contributor"
    end
  end
end

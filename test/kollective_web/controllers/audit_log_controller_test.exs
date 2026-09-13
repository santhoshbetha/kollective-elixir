defmodule KollectiveWeb.AuditLogControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.{AuditLog, OrganizationMembership}
  import Kollective.AccountsFixtures

  setup :authenticate_user

  setup %{user: user} do
    org = user_fixture(%{type: :organization, display_name: "Test Corp"})

    Repo.insert!(%OrganizationMembership{
      user_id: user.id,
      organization_id: org.id,
      role: :admin,
      status: :approved
    })

    %{org: org, user: user}
  end

  describe "GET /api/v1/org-settings/audit-logs" do
    test "lists audit logs for current organization context", %{conn: conn, org: org, user: user} do
      Repo.insert!(%AuditLog{
        action: "invite_sent",
        target_type: "membership",
        target_id: "fake_id",
        organization_id: org.id,
        actor_id: user.id
      })

      res =
        conn
        |> put_req_header("x-organization-id", to_string(org.id))
        |> get("/api/v1/org-settings/audit-logs")
        |> json_response(200)

      assert is_list(res["data"])
      assert length(res["data"]) >= 1
      log = hd(res["data"])
      assert log["action"] == "invite_sent"
    end
  end
end

defmodule KollectiveWeb.OrgAdminAuditChannelTest do
  use Kollective.DataCase, async: true
  import Phoenix.ChannelTest
  @endpoint KollectiveWeb.Endpoint

  alias KollectiveWeb.{UserSocket, OrgAdminAuditChannel}
  alias Kollective.Accounts.{Accounts, OrganizationMembership}
  alias Kollective.Repo
  import Kollective.AccountsFixtures

  setup do
    admin = user_fixture()
    admin_token = Accounts.generate_user_session_token(admin)

    member = user_fixture()
    member_token = Accounts.generate_user_session_token(member)

    org = user_fixture(%{type: :organization, display_name: "Audit Org"})

    Repo.insert!(%OrganizationMembership{
      user_id: admin.id,
      organization_id: org.id,
      role: :admin,
      status: :approved
    })

    Repo.insert!(%OrganizationMembership{
      user_id: member.id,
      organization_id: org.id,
      role: :contributor,
      status: :approved
    })

    %{
      admin: admin,
      admin_token: admin_token,
      member: member,
      member_token: member_token,
      org: org
    }
  end

  describe "OrgAdminAuditChannel join/3" do
    test "allows organization admin to join topic", %{admin_token: token, org: org} do
      {:ok, socket} = connect(UserSocket, %{"token" => token, "org_id" => org.id})

      assert {:ok, _reply, socket} =
               subscribe_and_join(socket, OrgAdminAuditChannel, "org_admin_audit:#{org.id}")

      assert socket.assigns.org_id == org.id
    end

    test "rejects regular contributor from joining admin audit topic", %{
      member_token: token,
      org: org
    } do
      {:ok, socket} = connect(UserSocket, %{"token" => token, "org_id" => org.id})

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, OrgAdminAuditChannel, "org_admin_audit:#{org.id}")
    end

    test "broadcasts new_audit_log to joined admin socket", %{admin_token: token, org: org} do
      {:ok, socket} = connect(UserSocket, %{"token" => token, "org_id" => org.id})

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, OrgAdminAuditChannel, "org_admin_audit:#{org.id}")

      payload = %{id: "log_1", action: "member_removed"}
      KollectiveWeb.Endpoint.broadcast!("org_admin_audit:#{org.id}", "new_audit_log", payload)

      assert_push "new_audit_log", ^payload
    end
  end
end

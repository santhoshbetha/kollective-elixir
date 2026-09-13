defmodule KollectiveWeb.UserSocketTest do
  use Kollective.DataCase, async: true
  import Phoenix.ChannelTest
  @endpoint KollectiveWeb.Endpoint

  alias KollectiveWeb.UserSocket
  alias Kollective.Accounts.{Accounts, OrganizationMembership}
  alias Kollective.Repo
  import Kollective.AccountsFixtures

  setup do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    org = user_fixture(%{type: :organization, display_name: "Audit Org"})

    %{user: user, token: token, org: org}
  end

  describe "UserSocket.connect/3" do
    test "connects successfully without org_id for standard user", %{token: token, user: user} do
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == user.id
      assert socket.assigns.is_authenticated == true
      refute Map.has_key?(socket.assigns, :org_id)
      assert UserSocket.id(socket) == "users_socket:#{user.id}"
    end

    test "connects successfully with org_id when user is an approved member", %{
      token: token,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :contributor,
        status: :approved
      })

      assert {:ok, socket} = connect(UserSocket, %{"token" => token, "org_id" => org.id})
      assert socket.assigns.user_id == user.id
      assert socket.assigns.org_id == org.id
      assert socket.assigns.current_org_id == org.id
      assert socket.assigns.org_membership.role == :contributor
    end

    test "rejects connection when user is not a member of the organization", %{
      token: token,
      org: org
    } do
      assert :error = connect(UserSocket, %{"token" => token, "org_id" => org.id})
    end

    test "rejects connection when user was removed from the organization", %{
      token: token,
      user: user,
      org: org
    } do
      membership =
        Repo.insert!(%OrganizationMembership{
          user_id: user.id,
          organization_id: org.id,
          role: :contributor,
          status: :approved
        })

      # Connect succeeds while approved
      assert {:ok, _socket} = connect(UserSocket, %{"token" => token, "org_id" => org.id})

      # Simulate member removal (either record deleted or status set to :removed)
      Repo.delete!(membership)

      # Connection is now rejected to prevent reconnecting and receiving broadcasts
      assert :error = connect(UserSocket, %{"token" => token, "org_id" => org.id})
    end

    test "rejects connection when user membership is still pending", %{
      token: token,
      user: user,
      org: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org.id,
        role: :contributor,
        status: :pending
      })

      assert :error = connect(UserSocket, %{"token" => token, "org_id" => org.id})
    end

    test "connects successfully when connecting as the organization itself", %{org: org} do
      org_token = Accounts.generate_user_session_token(org)

      assert {:ok, socket} = connect(UserSocket, %{"token" => org_token, "org_id" => org.id})
      assert socket.assigns.user_id == org.id
      assert socket.assigns.org_id == org.id
    end

    test "rejects connection with invalid token" do
      assert :error = connect(UserSocket, %{"token" => "invalid_token_12345"})
    end

    test "rejects connection without token" do
      assert :error = connect(UserSocket, %{})
    end
  end
end

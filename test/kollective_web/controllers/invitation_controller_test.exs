defmodule KollectiveWeb.InvitationControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.OrganizationMembership
  import Kollective.AccountsFixtures

  setup :authenticate_user

  setup %{user: user} do
    org = user_fixture(%{type: :organization, display_name: "Acme Corp"})
    %{org: org, user: user}
  end

  describe "InvitationController" do
    test "GET /api/v1/invitations lists pending invites", %{
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
        |> get("/api/v1/invitations")
        |> json_response(200)

      assert is_list(res["data"])
      assert Enum.any?(res["data"], fn item -> item["id"] == to_string(membership.id) end)
    end

    test "POST /api/v1/invitations/:id/accept accepts invitation", %{
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

    test "POST /api/v1/invitations/:id/accept returns 404 for non-existent invitation", %{
      conn: conn
    } do
      fake_id = Ecto.ULID.generate()

      conn
      |> post("/api/v1/invitations/#{fake_id}/accept")
      |> json_response(404)
    end
  end
end

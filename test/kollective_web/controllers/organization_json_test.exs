defmodule KollectiveWeb.OrganizationJSONTest do
  use ExUnit.Case, async: true

  alias KollectiveWeb.OrganizationJSON
  alias Kollective.Accounts.{OrganizationMembership, User}

  describe "OrganizationJSON serialization" do
    test "data/1 and show/1 render organization details" do
      now = ~U[2026-09-12 12:00:00Z]

      org = %User{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7AA",
        username: "green_peace",
        display_name: "Green Peace Action",
        avatar_url: "https://example.com/green.jpg",
        bio: "Environmental advocacy network",
        type: :organization,
        inserted_at: now
      }

      data = OrganizationJSON.data(org)
      assert data.id == "01J7K8M9N0P1Q2R3S4T5U6V7AA"
      assert data.username == "green_peace"
      assert data.type == :organization

      show_res = OrganizationJSON.show(%{organization: org})
      assert show_res.data == data

      index_res = OrganizationJSON.index(%{organizations: [org]})
      assert index_res.data == [data]
    end

    test "membership/1 serializes membership" do
      now = ~U[2026-09-12 12:00:00Z]

      m = %OrganizationMembership{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7BB",
        user_id: "01J7K8M9N0P1Q2R3S4T5U6V7CC",
        organization_id: "01J7K8M9N0P1Q2R3S4T5U6V7DD",
        role: :admin,
        status: :approved,
        inserted_at: now
      }

      data = OrganizationJSON.membership(m)
      assert data.id == "01J7K8M9N0P1Q2R3S4T5U6V7BB"
      assert data.role == :admin
      assert data.status == :approved
    end

    test "invite_success/3, join_request_success/0, ownership_transferred/0 return expected contracts" do
      m = %{id: "01J7K8M9N0P1Q2R3S4T5U6V7BB", role: :contributor}
      res = OrganizationJSON.invite_success("Invitation sent.", m, "invitee@example.com")
      assert res.status == "success"
      assert res.data.email == "invitee@example.com"
      assert res.data.role == :contributor

      join_res = OrganizationJSON.join_request_success()
      assert join_res.status == "success"

      transfer_res = OrganizationJSON.ownership_transferred()
      assert transfer_res.status == "success"
    end
  end
end

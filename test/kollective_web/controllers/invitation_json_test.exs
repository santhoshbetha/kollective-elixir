defmodule KollectiveWeb.InvitationJSONTest do
  use ExUnit.Case, async: true

  alias KollectiveWeb.InvitationJSON
  alias Kollective.Accounts.{OrganizationMembership, User}

  describe "InvitationJSON serialization" do
    test "index/1 and show/1 serializes memberships and nested org" do
      now = ~U[2026-09-12 12:00:00Z]

      org = %User{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7AA",
        username: "kollective_org",
        display_name: "Kollective HQ",
        avatar_url: "https://example.com/avatar.jpg"
      }

      membership = %OrganizationMembership{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7BB",
        role: :contributor,
        status: :pending,
        inserted_at: now,
        organization: org
      }

      index_res = InvitationJSON.index(%{invitations: [membership]})
      assert is_list(index_res.data)
      assert length(index_res.data) == 1

      first = hd(index_res.data)
      assert first.id == "01J7K8M9N0P1Q2R3S4T5U6V7BB"
      assert first.role == :contributor
      assert first.status == :pending
      assert first.organization.username == "kollective_org"

      show_res = InvitationJSON.show(%{membership: membership})
      assert show_res.data == first

      # Bare argument overloads
      assert InvitationJSON.index([membership]) == index_res
      assert InvitationJSON.show(membership) == show_res
    end

    test "handles unloaded organization safely" do
      membership = %OrganizationMembership{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7BB",
        role: :admin,
        status: :approved,
        inserted_at: ~U[2026-09-12 12:00:00Z],
        organization: %Ecto.Association.NotLoaded{}
      }

      data = InvitationJSON.data(membership)
      assert data.organization == nil
    end
  end
end

defmodule KollectiveWeb.OrganizationAdminJSONTest do
  use ExUnit.Case, async: true

  alias KollectiveWeb.OrganizationAdminJSON
  alias Kollective.Accounts.{OrganizationMembership, User}

  describe "OrganizationAdminJSON serialization" do
    test "pending_members/1 serializes pending requests and nested user profile" do
      now = ~U[2026-09-12 12:00:00Z]

      user = %User{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7AA",
        username: "applicant_bob",
        avatar_url: "https://example.com/bob.jpg"
      }

      membership = %OrganizationMembership{
        id: "01J7K8M9N0P1Q2R3S4T5U6V7BB",
        role: :contributor,
        status: :pending,
        inserted_at: now,
        user: user
      }

      res = OrganizationAdminJSON.pending_members([membership])
      assert res.status == "success"
      assert is_list(res.data)
      assert length(res.data) == 1

      first = hd(res.data)
      assert first.membership_id == "01J7K8M9N0P1Q2R3S4T5U6V7BB"
      assert first.role == :contributor
      assert first.inserted_at == "2026-09-12T12:00:00Z"
      assert first.user.id == "01J7K8M9N0P1Q2R3S4T5U6V7AA"
      assert first.user.username == "applicant_bob"
      assert first.user.avatar_url == "https://example.com/bob.jpg"
    end

    test "action_success/1 returns success status with message" do
      res = OrganizationAdminJSON.action_success("Role updated successfully.")
      assert res == %{status: "success", message: "Role updated successfully."}
    end
  end
end

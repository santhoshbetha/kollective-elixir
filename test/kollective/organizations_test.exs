defmodule Kollective.OrganizationsTest do
  use Kollective.DataCase, async: true
  import Swoosh.TestAssertions

  alias Kollective.Accounts.{Accounts, Organizations, OrganizationMembership}
  alias Kollective.Repo

  import Kollective.AccountsFixtures

  setup do
    # 1. Human users
    user = user_fixture(%{display_name: "Bob Contributor", username: "bob_writes"})
    member_user = user_fixture(%{display_name: "Alice Member", username: "alice_member"})

    # 2. Organization spaces
    org_alpha =
      user_fixture(%{
        type: :organization,
        display_name: "Alpha Network",
        username: "alpha_org"
      })

    org_beta =
      user_fixture(%{
        type: :organization,
        display_name: "Beta Network",
        username: "beta_org"
      })

    %{
      user: user,
      member_user: member_user,
      org_alpha: org_alpha,
      org_beta: org_beta
    }
  end

  describe "list_pending_invitations/1 status filters" do
    test "returns only memberships that are explicitly marked as pending", %{
      user: user,
      org_alpha: org_alpha,
      org_beta: org_beta
    } do
      # 1. Insert a PENDING membership for Org Alpha (Should be surfaced)
      {:ok, pending_membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org_alpha.id,
          role: :contributor,
          status: :pending
        })

      # 2. Insert an APPROVED membership for Org Beta (Should be filtered out)
      {:ok, _approved_membership} =
        Repo.insert(%OrganizationMembership{
          user_id: user.id,
          organization_id: org_beta.id,
          role: :admin,
          status: :approved
        })

      # 3. Invoke query via both Organizations and Accounts delegation
      results = Organizations.list_pending_invitations(user.id)
      delegated_results = Accounts.list_pending_invitations(user.id)

      # 4. Assertions
      assert length(results) == 1
      assert length(delegated_results) == 1

      [fetched_invite] = results
      assert fetched_invite.id == pending_membership.id
      assert fetched_invite.status == :pending
      assert fetched_invite.role == :contributor
      assert fetched_invite.organization_id == org_alpha.id

      # Confirm preloaded organization relationship
      assert fetched_invite.organization.id == org_alpha.id
      assert fetched_invite.organization.display_name == "Alpha Network"
    end

    test "returns an empty list if the user has no invitations at all" do
      random_user_id = Kollective.Schemas.ULIDType.generate()

      assert Organizations.list_pending_invitations(random_user_id) == []
      assert Accounts.list_pending_invitations(random_user_id) == []
    end
  end

  describe "invitations lifecycle" do
    test "create_invite/3 creates a pending membership and handles errors", %{
      user: user,
      org_alpha: org_alpha
    } do
      {:ok, membership} = Organizations.create_invite(org_alpha.id, user.email, :contributor)
      assert membership.user_id == user.id
      assert membership.organization_id == org_alpha.id
      assert membership.role == :contributor
      assert membership.status == :pending

      # Inviting non-existent email returns error
      assert Organizations.create_invite(org_alpha.id, "unknown@test.com", :contributor) ==
               {:error, :user_not_found}
    end

    test "resend_invite/2 enqueues notification or returns authorization error", %{
      user: user,
      org_alpha: org_alpha,
      org_beta: org_beta
    } do
      {:ok, membership} = Organizations.create_invite(org_alpha.id, user.email, :contributor)

      # Valid resend enqueues an Oban job
      assert {:ok, _} = Organizations.resend_invite(org_alpha.id, membership.id)

      # Wrong org returns unauthorized
      assert Organizations.resend_invite(org_beta.id, membership.id) == {:error, :unauthorized}

      # Non-existent membership returns invalid_invite
      fake_id = Kollective.Schemas.ULIDType.generate()
      assert Organizations.resend_invite(org_alpha.id, fake_id) == {:error, :invalid_invite}
    end

    test "remove_invite/2 marks membership as removed", %{user: user, org_alpha: org_alpha} do
      {:ok, membership} = Organizations.create_invite(org_alpha.id, user.email, :contributor)

      assert {:ok, removed} = Organizations.remove_invite(org_alpha.id, membership.id)
      assert removed.status == :removed

      # Cannot remove non-existent invite
      fake_id = Kollective.Schemas.ULIDType.generate()
      assert Organizations.remove_invite(org_alpha.id, fake_id) == {:error, :invalid_invite}
    end

    test "accept_invitation/2 approves pending membership", %{user: user, org_alpha: org_alpha} do
      {:ok, membership} = Organizations.create_invite(org_alpha.id, user.email, :contributor)

      assert {:ok, approved} = Organizations.accept_invitation(user.id, membership.id)
      assert approved.status == :approved

      # Cannot accept again once not pending
      assert Organizations.accept_invitation(user.id, membership.id) == {:error, :not_found}
    end

    test "decline_invitation/2 deletes pending membership", %{user: user, org_alpha: org_alpha} do
      {:ok, membership} = Organizations.create_invite(org_alpha.id, user.email, :contributor)

      assert {:ok, _deleted} = Organizations.decline_invitation(user.id, membership.id)
      assert Repo.get(OrganizationMembership, membership.id) == nil

      # Cannot decline again
      assert Organizations.decline_invitation(user.id, membership.id) == {:error, :not_found}
    end
  end

  describe "join requests and authorization" do
    test "request_organization_join/2 validates target account type", %{
      user: user,
      org_alpha: org_alpha,
      member_user: non_org_user
    } do
      {:ok, membership} = Organizations.request_organization_join(user.id, org_alpha.id)
      assert membership.status == :pending
      assert membership.user_id == user.id
      assert membership.organization_id == org_alpha.id

      # Cannot request to join non-organization account
      assert Organizations.request_organization_join(user.id, non_org_user.id) ==
               {:error, :invalid_target_account}
    end

    test "process_join_request/3 enforces admin authority", %{
      user: user,
      org_alpha: org_alpha,
      member_user: admin_user
    } do
      # Make admin_user an approved admin of org_alpha
      {:ok, _admin_membership} =
        Repo.insert(%OrganizationMembership{
          user_id: admin_user.id,
          organization_id: org_alpha.id,
          role: :admin,
          status: :approved
        })

      {:ok, pending_request} = Organizations.request_organization_join(user.id, org_alpha.id)

      # Non-admin cannot process join request
      non_admin = user_fixture()

      assert Organizations.process_join_request(non_admin, pending_request.id, :approved) ==
               {:error, :unauthorized}

      # Admin can approve
      assert {:ok, %{membership: approved}} =
               Organizations.process_join_request(admin_user, pending_request.id, :approved)

      assert approved.status == :approved
    end

    test "list_authorized_organizations/1 returns approved organizations", %{
      user: user,
      org_alpha: org_alpha,
      org_beta: org_beta
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org_alpha.id,
        role: :contributor,
        status: :approved
      })

      Repo.insert!(%OrganizationMembership{
        user_id: user.id,
        organization_id: org_beta.id,
        role: :contributor,
        status: :pending
      })

      orgs = Organizations.list_authorized_organizations(user.id)
      assert length(orgs) == 1
      assert hd(orgs).id == org_alpha.id
    end

    test "search_organizations_by_type/1 finds organizations by username or display_name", %{
      org_alpha: org_alpha
    } do
      # Search by username substring
      results = Organizations.search_organizations_by_type("alpha")
      assert Enum.any?(results, &(&1.id == org_alpha.id))

      # Search by display_name substring
      results2 = Organizations.search_organizations_by_type("Network")
      assert Enum.any?(results2, &(&1.id == org_alpha.id))

      # Empty query returns empty list
      assert Organizations.search_organizations_by_type("") == []
      assert Organizations.search_organizations_by_type("   ") == []
    end
  end

  describe "ownership and roles" do
    test "transfer_ownership/3 atomically swaps roles", %{
      user: owner,
      member_user: new_owner,
      org_alpha: org
    } do
      Repo.insert!(%OrganizationMembership{
        user_id: owner.id,
        organization_id: org.id,
        role: :owner,
        status: :approved
      })

      Repo.insert!(%OrganizationMembership{
        user_id: new_owner.id,
        organization_id: org.id,
        role: :admin,
        status: :approved
      })

      assert Organizations.is_owner?(org.id, owner.id) == true
      assert Organizations.is_owner?(org.id, new_owner.id) == false

      {:ok, _} = Organizations.transfer_ownership(org.id, owner.id, new_owner.id)

      assert Organizations.is_owner?(org.id, owner.id) == false
      assert Organizations.is_owner?(org.id, new_owner.id) == true

      # Check membership roles in DB
      demoted = Organizations.get_organization_membership_by_user(owner.id, org.id)
      assert demoted.role == :admin

      promoted = Organizations.get_organization_membership_by_user(new_owner.id, org.id)
      assert promoted.role == :owner
    end

    test "count_organization_owners/1 counts only approved owners", %{
      user: user1,
      member_user: user2,
      org_alpha: org
    } do
      assert Organizations.count_organization_owners(org.id) == 0

      # Pending owner does not count
      Repo.insert!(%OrganizationMembership{
        user_id: user1.id,
        organization_id: org.id,
        role: :owner,
        status: :pending
      })

      assert Organizations.count_organization_owners(org.id) == 0

      # Approved owner counts
      Repo.insert!(%OrganizationMembership{
        user_id: user2.id,
        organization_id: org.id,
        role: :owner,
        status: :approved
      })

      assert Organizations.count_organization_owners(org.id) == 1
    end
  end

  test "delete_organization/1 deletes the org and cascades to purge its posts", %{user: user} do
    # 1. Create a target organization
    {:ok, org} =
      Repo.insert(%Kollective.Accounts.User{
        username: "to_be_deleted_org",
        display_name: "To Be Deleted",
        email: "[EMAIL_ADDRESS]",
        password: "[PASSWORD]"
      })

    # 2. Create an organization post
    {:ok, org_post} =
      Repo.insert(%Kollective.Posts.Post{
        content: "Org Post",
        user_id: user.id,
        organization_id: org.id
      })

    # 3. Create a personal post completely separate from the company
    {:ok, personal_post} =
      Repo.insert(%Kollective.Posts.Post{
        content: "Personal Post",
        user_id: user.id,
        organization_id: nil
      })

    # 4. Trigger the permanent purge function
    assert {:ok, _} = Organizations.delete_organization(org.id)

    # 5. Assert the company and its specific timeline rows are completely gone
    refute Repo.get(Kollective.Accounts.User, org.id)
    refute Repo.get(Kollective.Posts.Post, org_post.id)

    # 6. Assert that personal user content remains safe and unaffected
    assert Repo.get(Kollective.Posts.Post, personal_post.id)
  end

  test "create_invite/3 sends an async transactional email notification to the recipient", %{
    user: user,
    org_alpha: org
  } do
    # Drain any setup emails sent during user_fixture creation
    clear_mailbox = fn clear ->
      receive do
        {:email, _} -> clear.(clear)
      after
        0 -> :ok
      end
    end

    clear_mailbox.(clear_mailbox)

    # Trigger the context method
    assert {:ok, _membership} = Organizations.create_invite(org.id, user.email, "contributor")

    # Await the asynchronous email delivery from Task.start
    assert_receive {:email, email}, 1000
    send(self(), {:email, email})

    # Assert Swoosh caught the outbound email compilation details accurately
    assert_email_sent(
      to: {user.display_name, user.email},
      subject: "You have been invited to join #{org.display_name}!"
    )
  end
end

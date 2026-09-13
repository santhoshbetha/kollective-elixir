defmodule Kollective.Posts.OrganizationPostTest do
  use Kollective.DataCase

  alias Kollective.Posts.{Post, Posts}
  alias Kollective.Accounts.{User, AuditLog, OrganizationMembership}
  alias Kollective.Repo

  import Kollective.AccountsFixtures

  setup do
    user = user_fixture(%{display_name: "Human Individual"})
    org = user_fixture(%{type: :organization, display_name: "Civic Action Org"})
    %{user: user, org: org}
  end

  describe "post ownership: personal vs organization" do
    test "personal post sets user_id and leaves organization_id nil", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "My personal thought of the day",
          "visibility" => "public"
        })

      assert post.user_id == user.id
      assert is_nil(post.organization_id)

      # Reload from DB and verify associations
      db_post = Repo.get!(Post, post.id) |> Repo.preload([:author, :organization])
      assert db_post.user_id == user.id
      assert db_post.author.id == user.id
      assert is_nil(db_post.organization_id)
      assert is_nil(db_post.organization)
    end

    test "org post sets user_id to individual author and organization_id to org", %{
      user: user,
      org: org
    } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Official statement published by staff member",
          "visibility" => "public",
          "organization_id" => org.id
        })

      assert post.user_id == user.id
      assert post.organization_id == org.id

      # Reload from DB and verify associations
      db_post = Repo.get!(Post, post.id) |> Repo.preload([:author, :organization])
      assert db_post.user_id == user.id
      assert db_post.author.id == user.id
      assert db_post.organization_id == org.id

      # Also verify both author and organization note counts were updated
      fresh_user = Repo.get!(User, user.id)
      fresh_org = Repo.get!(User, org.id)
      assert fresh_user.note_count == 1
      assert fresh_org.note_count == 1
    end

    test "direct post by organization account sets user_id and organization_id to org id", %{
      org: org
    } do
      {:ok, post} =
        Posts.create_post(org, %{
          "content" => "Direct post from org account",
          "visibility" => "public"
        })

      assert post.user_id == org.id
      assert post.organization_id == org.id
    end

    test "get_post/1 preloads both author and organization", %{user: user, org: org} do
      {:ok, created} =
        Posts.create_post(user, %{
          "content" => "Post with organization",
          "visibility" => "public",
          "organization_id" => org.id
        })

      {:ok, fetched} = Posts.get_post(created.id)
      assert fetched.author.id == user.id
      assert fetched.organization.id == org.id
    end
  end

  describe "edit_count tracking" do
    test "newly created post has edit_count of 0 and edited_at nil", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Original text",
          "visibility" => "public"
        })

      assert post.edit_count == 0
      assert is_nil(post.edited_at)

      reloaded = Repo.get!(Post, post.id)
      assert reloaded.edit_count == 0
      assert is_nil(reloaded.edited_at)
    end

    test "update_post increments edit_count and updates edited_at on content change", %{
      user: user
    } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Version 1",
          "visibility" => "public"
        })

      assert post.edit_count == 0

      # First edit
      {:ok, updated1} = Posts.update_post(post, %{"content" => "Version 2"})
      assert updated1.content == "Version 2"
      assert updated1.edit_count == 1
      assert updated1.edited_at != nil

      # Second edit
      {:ok, updated2} = Posts.update_post(updated1, %{"content" => "Version 3"})
      assert updated2.content == "Version 3"
      assert updated2.edit_count == 2
      assert updated2.edited_at != nil

      # Update with no actual changes does not increment edit_count
      {:ok, untouched} = Posts.update_post(updated2, %{})
      assert untouched.edit_count == 2
    end
  end

  describe "AuditLog in update_post" do
    test "records AuditLog when an organization post is updated", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org announcement version 1",
          "visibility" => "public",
          "organization_id" => org.id
        })

      admin = user_fixture(%{display_name: "Org Admin"})

      {:ok, updated} =
        Posts.update_post(post, %{
          "content" => "Org announcement version 2",
          "actor_id" => admin.id
        })

      assert updated.content == "Org announcement version 2"
      assert updated.edit_count == 1

      # Verify AuditLog entry was created
      log =
        Repo.get_by(AuditLog,
          action: "post_edited",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log != nil
      assert log.actor_id == admin.id
      assert log.organization_id == org.id
      assert log.metadata["new_edit_count"] == 1
      assert log.metadata["is_admin_edit"] == true
    end

    test "records AuditLog with is_admin_edit: false when author updates their own org post", %{
      user: user,
      org: org
    } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org announcement by author v1",
          "visibility" => "public",
          "organization_id" => org.id
        })

      {:ok, updated} =
        Posts.update_post(post, %{
          "content" => "Org announcement by author v2",
          "actor_id" => user.id
        })

      assert updated.content == "Org announcement by author v2"

      log =
        Repo.get_by(AuditLog,
          action: "post_edited",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log != nil
      assert log.actor_id == user.id
      assert log.organization_id == org.id
      assert log.metadata["is_admin_edit"] == false
    end

    test "does not record AuditLog when a personal post is updated", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Personal post v1",
          "visibility" => "public"
        })

      {:ok, updated} = Posts.update_post(post, %{"content" => "Personal post v2"})
      assert updated.content == "Personal post v2"
      assert updated.edit_count == 1

      # No audit log should exist for personal post
      log =
        Repo.get_by(AuditLog,
          action: "post_edited",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log == nil
    end
  end

  describe "AuditLog in delete_post" do
    test "records AuditLog when an organization post is deleted", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org announcement to be deleted",
          "visibility" => "public",
          "organization_id" => org.id
        })

      admin = user_fixture(%{display_name: "Org Admin"})

      {:ok, deleted} = Posts.delete_post(post, actor_id: admin.id)
      assert deleted.id == post.id
      assert Repo.get(Post, post.id) == nil

      # Verify AuditLog entry was created for post deletion
      log =
        Repo.get_by(AuditLog,
          action: "post_deleted",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log != nil
      assert log.actor_id == admin.id
      assert log.organization_id == org.id
      assert log.metadata["content_snippet"] =~ "Org announcement"
      assert log.metadata["is_admin_delete"] == true
    end

    test "records AuditLog with is_admin_delete: false when author deletes their own org post", %{
      user: user,
      org: org
    } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org post by author to delete",
          "visibility" => "public",
          "organization_id" => org.id
        })

      {:ok, _deleted} = Posts.delete_post(post, actor_id: user.id)

      log =
        Repo.get_by(AuditLog,
          action: "post_deleted",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log != nil
      assert log.actor_id == user.id
      assert log.organization_id == org.id
      assert log.metadata["is_admin_delete"] == false
    end

    test "does not record AuditLog when a personal post is deleted", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Personal post to delete",
          "visibility" => "public"
        })

      {:ok, _deleted} = Posts.delete_post(post)
      assert Repo.get(Post, post.id) == nil

      log =
        Repo.get_by(AuditLog,
          action: "post_deleted",
          target_type: "Post",
          target_id: to_string(post.id)
        )

      assert log == nil
    end
  end

  describe "AuditLog in restore_post" do
    test "records AuditLog when an organization post is restored", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Rejected org post",
          "visibility" => "public",
          "organization_id" => org.id
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Mark post as rejected
      post
      |> Ecto.Changeset.change(%{
        status: :rejected,
        rejected_at: now,
        rejection_reason: "Automated flag"
      })
      |> Repo.update!()

      admin = user_fixture(%{display_name: "Platform Admin"})

      Repo.insert!(%OrganizationMembership{
        organization_id: org.id,
        user_id: admin.id,
        role: :admin,
        status: :approved
      })

      {:ok, restored} = Posts.restore_post(admin, post.id)
      assert restored.status == :published
      assert is_nil(restored.rejected_at)

      # Verify AuditLog entry was created
      log =
        Repo.get_by(AuditLog,
          action: "post_restored",
          target_type: "Post",
          target_id: post.id
        )

      assert log != nil
      assert log.actor_id == admin.id
      assert log.organization_id == org.id
      assert log.metadata["original_author_id"] == user.id
      assert log.metadata["is_admin_override"] == true
    end

    test "records AuditLog with is_admin_override: false when author restores their own org post",
         %{
           user: user,
           org: org
         } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Rejected org post restored by author",
          "visibility" => "public",
          "organization_id" => org.id
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      post
      |> Ecto.Changeset.change(%{
        status: :rejected,
        rejected_at: now,
        rejection_reason: "Temporary flag"
      })
      |> Repo.update!()

      {:ok, restored} = Posts.restore_post(user, post.id)
      assert restored.status == :published

      log =
        Repo.get_by(AuditLog,
          action: "post_restored",
          target_type: "Post",
          target_id: post.id
        )

      assert log != nil
      assert log.actor_id == user.id
      assert log.organization_id == org.id
      assert log.metadata["original_author_id"] == user.id
      assert log.metadata["is_admin_override"] == false
    end

    test "does not record AuditLog when a personal post is restored", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Rejected personal post",
          "visibility" => "public"
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Mark post as rejected
      post
      |> Ecto.Changeset.change(%{
        status: :rejected,
        rejected_at: now
      })
      |> Repo.update!()

      {:ok, restored} = Posts.restore_post(user, post.id)
      assert restored.status == :published

      log =
        Repo.get_by(AuditLog,
          action: "post_restored",
          target_type: "Post",
          target_id: post.id
        )

      assert log == nil
    end
  end

  describe "authorize_restore" do
    test "author can restore their personal post", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Personal post",
          "visibility" => "public"
        })

      assert Posts.authorize_restore(post, user) == :ok
      assert Posts.authorize_restore(user, post) == :ok
      assert Posts.authorize_restore?(post, user) == true
      assert Posts.authorize_restore?(user, post) == true
      assert Posts.authorize_restore(post.id, user) == :ok
    end

    test "non-author cannot restore a personal post", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Personal post",
          "visibility" => "public"
        })

      other_user = user_fixture()

      assert Posts.authorize_restore(post, other_user) == {:error, :unauthorized}
      assert Posts.authorize_restore(other_user, post) == {:error, :unauthorized}
      assert Posts.authorize_restore?(post, other_user) == false
      assert Posts.restore_post(other_user, post.id) == {:error, :unauthorized}
    end

    test "author of an org post can restore it", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org post by contributor",
          "visibility" => "public",
          "organization_id" => org.id
        })

      assert Posts.authorize_restore(post, user) == :ok
      assert Posts.authorize_restore?(post, user) == true
    end

    test "org admin or owner can restore an org post", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org post",
          "visibility" => "public",
          "organization_id" => org.id
        })

      admin = user_fixture(%{display_name: "Org Admin"})

      Repo.insert!(%OrganizationMembership{
        organization_id: org.id,
        user_id: admin.id,
        role: :admin,
        status: :approved
      })

      owner = user_fixture(%{display_name: "Org Owner"})

      Repo.insert!(%OrganizationMembership{
        organization_id: org.id,
        user_id: owner.id,
        role: :owner,
        status: :approved
      })

      assert Posts.authorize_restore(post, admin) == :ok
      assert Posts.authorize_restore?(post, admin) == true
      assert Posts.authorize_restore(post, owner) == :ok
      assert Posts.authorize_restore?(post, owner) == true
    end

    test "non-admin/owner org member or outsider cannot restore an org post", %{
      user: user,
      org: org
    } do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org post",
          "visibility" => "public",
          "organization_id" => org.id
        })

      contributor = user_fixture(%{display_name: "Contributor"})

      Repo.insert!(%OrganizationMembership{
        organization_id: org.id,
        user_id: contributor.id,
        role: :contributor,
        status: :approved
      })

      outsider = user_fixture(%{display_name: "Outsider"})

      assert Posts.authorize_restore(post, contributor) == {:error, :unauthorized}
      assert Posts.authorize_restore?(post, contributor) == false
      assert Posts.restore_post(contributor, post.id) == {:error, :unauthorized}

      assert Posts.authorize_restore(post, outsider) == {:error, :unauthorized}
      assert Posts.authorize_restore?(post, outsider) == false
      assert Posts.restore_post(outsider, post.id) == {:error, :unauthorized}
    end

    test "organization entity itself can restore an org post", %{user: user, org: org} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Org post restored by org",
          "visibility" => "public",
          "organization_id" => org.id
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      post
      |> Ecto.Changeset.change(%{status: :rejected, rejected_at: now})
      |> Repo.update!()

      assert Posts.authorize_restore(post, org) == :ok
      assert Posts.authorize_restore?(post, org) == true
      assert {:ok, restored} = Posts.restore_post(org, post.id)
      assert restored.status == :published
    end

    test "authorize_restore returns {:error, :not_found} for non-existent post id", %{user: user} do
      fake_id = Kollective.Schemas.ULIDType.generate()
      assert Posts.authorize_restore(fake_id, user) == {:error, :not_found}
      assert Posts.authorize_restore?(fake_id, user) == false
    end
  end
end

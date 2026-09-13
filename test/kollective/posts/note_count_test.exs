defmodule Kollective.Posts.NoteCountTest do
  use Kollective.DataCase

  alias Kollective.Posts.Posts
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User
  alias Kollective.Moderation.Moderation
  alias Kollective.Repo

  import Kollective.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "note_count tracking" do
    test "create_post increments note_count and updates last_post_at", %{user: user} do
      assert user.note_count == 0
      assert user.last_post_at == nil

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Hello world from note_count test!",
          "visibility" => "public"
        })

      fresh_user = Repo.get!(User, user.id)
      assert fresh_user.note_count == 1
      assert fresh_user.last_post_at != nil

      # Creating a second post increments again
      {:ok, _post2} =
        Posts.create_post(fresh_user, %{
          "content" => "Second post!",
          "visibility" => "public"
        })

      fresh_user2 = Repo.get!(User, user.id)
      assert fresh_user2.note_count == 2

      # Deleting a post decrements note_count
      {:ok, _deleted} = Posts.delete_post(post)

      fresh_user3 = Repo.get!(User, user.id)
      assert fresh_user3.note_count == 1
    end

    test "create_reply increments reply author's note_count", %{user: user} do
      {:ok, root_post} =
        Posts.create_post(user, %{
          "content" => "Root thread starter",
          "visibility" => "public"
        })

      replier = user_fixture()
      assert replier.note_count == 0

      {:ok, _reply} =
        Posts.create_reply(replier, root_post, %{
          "content" => "I am replying here!"
        })

      fresh_replier = Repo.get!(User, replier.id)
      assert fresh_replier.note_count == 1
      assert fresh_replier.last_post_at != nil
    end

    test "reblogging increments note_count and unreblogging decrements it", %{user: user} do
      other_user = user_fixture()

      {:ok, post} =
        Posts.create_post(other_user, %{
          "content" => "Boostable content",
          "visibility" => "public"
        })

      assert user.note_count == 0

      # Boost the post
      {:ok, :reblogged, _reblog} = Posts.reblog_post(user.id, post.id)

      fresh_user = Repo.get!(User, user.id)
      assert fresh_user.note_count == 1
      assert fresh_user.last_post_at != nil

      # Retract the boost (unreblog)
      {:ok, :unreblogged} = Posts.reblog_post(user.id, post.id)

      fresh_user2 = Repo.get!(User, user.id)
      assert fresh_user2.note_count == 0
    end

    test "admin_delete_post decrements author's note_count", %{user: user} do
      admin = user_fixture(%{is_admin: true, role: :admin})

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Violating post",
          "visibility" => "public"
        })

      fresh_user = Repo.get!(User, user.id)
      assert fresh_user.note_count == 1

      {:ok, :deleted} = Moderation.admin_delete_post(admin, post.id)

      fresh_user2 = Repo.get!(User, user.id)
      assert fresh_user2.note_count == 0
    end

    test "decrementing note_count does not go below zero", %{user: user} do
      assert user.note_count == 0

      Accounts.decrement_note_count(user.id)

      fresh_user = Repo.get!(User, user.id)
      assert fresh_user.note_count == 0
    end
  end
end

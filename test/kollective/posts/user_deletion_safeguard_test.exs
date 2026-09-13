defmodule Kollective.Posts.UserDeletionSafeguardTest do
  use Kollective.DataCase

  alias Kollective.Posts.Posts
  alias Kollective.Posts.Post
  alias Kollective.Repo
  alias KollectiveWeb.PostJSON

  import Kollective.AccountsFixtures

  test "post is preserved and user_id is nilified when author user account is deleted" do
    user = user_fixture()

    {:ok, post} =
      Posts.create_post(user, %{
        "content" => "This post must survive author account deletion!",
        "visibility" => "public"
      })

    assert post.user_id == user.id

    # Delete the user account entirely from the database
    Repo.delete!(user)

    # Verify post still exists in DB with user_id nilified
    reloaded_post = Repo.get!(Post, post.id) |> Repo.preload([:author, :organization])
    assert reloaded_post.id == post.id
    assert is_nil(reloaded_post.user_id)
    assert is_nil(reloaded_post.author)
    assert reloaded_post.content == "This post must survive author account deletion!"

    # Verify JSON serialization handles nil author gracefully
    serialized = PostJSON.show(reloaded_post)
    assert serialized.id == to_string(post.id)
    assert is_nil(serialized.author)
  end

  test "existing post user_id cannot be changed once created (immutability check)" do
    user1 = user_fixture()
    user2 = user_fixture()

    {:ok, post} =
      Posts.create_post(user1, %{
        "content" => "Original author content",
        "visibility" => "public"
      })

    changeset = Post.changeset(post, %{user_id: user2.id, content: "Updated content"})
    refute changeset.valid?
    assert "cannot be changed once post is created" in errors_on(changeset).user_id
  end

  test "post with deleted author can be liked without crashing" do
    user = user_fixture()
    liker = user_fixture()

    {:ok, post} =
      Posts.create_post(user, %{
        "content" => "Post to be liked after author deletion",
        "visibility" => "public"
      })

    # Author deleted
    Repo.delete!(user)

    # Liking the post whose author was deleted must succeed smoothly
    assert {:ok, :liked} = Posts.toggle_like(liker.id, post.id)
    assert Posts.get_like_count(post.id) == 1
  end

  test "post with deleted author can be deleted without failing note count decrement" do
    user = user_fixture()

    {:ok, post} =
      Posts.create_post(user, %{
        "content" => "Post to be deleted after author deletion",
        "visibility" => "public"
      })

    # Author deleted
    Repo.delete!(user)
    reloaded_post = Repo.get!(Post, post.id)

    # Deleting the post should succeed
    assert {:ok, _deleted} = Posts.delete_post(reloaded_post)
    assert is_nil(Repo.get(Post, post.id))
  end

  test "replying to a post whose author is deleted does not crash workers" do
    user = user_fixture()
    replier = user_fixture()

    {:ok, parent_post} =
      Posts.create_post(user, %{
        "content" => "Parent post before author deletion",
        "visibility" => "public"
      })

    # Author deleted
    Repo.delete!(user)
    parent_post = Repo.get!(Post, parent_post.id)

    # Creating reply to parent post with nil user_id
    assert {:ok, reply} =
             Posts.create_reply(replier, parent_post, %{
               "content" => "Replying to orphaned post",
               "visibility" => "public"
             })

    assert reply.in_reply_to_id == parent_post.id
  end

  test "virtual field hydration and reaction formatting handle empty/nil reactions gracefully" do
    user = user_fixture()

    {:ok, post} =
      Posts.create_post(user, %{
        "content" => "Post testing emoji reactions",
        "visibility" => "public"
      })

    # Hydrate with current user
    [hydrated_with_user] = Posts.hydrate_virtual_fields([post], user)
    assert is_map(hydrated_with_user.post.emoji_reactions)

    # Hydrate with anonymous/nil user
    [hydrated_anon] = Posts.hydrate_virtual_fields([post], nil)
    assert is_map(hydrated_anon.post.emoji_reactions)
  end
end

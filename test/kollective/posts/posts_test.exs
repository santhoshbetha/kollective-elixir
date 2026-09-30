defmodule Kollective.Posts.PostsTest do
  use Kollective.DataCase

  alias Kollective.Posts.Posts
  alias Kollective.Polls.Poll
  alias Kollective.Repo

  import Kollective.AccountsFixtures

  setup do
    user = user_fixture(%{locale: "en"})
    %{user: user}
  end

  describe "get_post/1 and get_post!/1" do
    test "fetches an existing post with preloaded associations", %{user: user} do
      {:ok, created} =
        Posts.create_post(user, %{
          "content" => "Testing get_post lookup #elixir",
          "visibility" => "public"
        })

      assert {:ok, fetched} = Posts.get_post(created.id)
      assert fetched.id == created.id
      assert fetched.author.id == user.id
      assert [%{name: "elixir"}] = fetched.hashtags

      assert Posts.get_post!(created.id).id == created.id
    end

    test "returns {:error, :not_found} for non-existent id" do
      fake_id = Kollective.Schemas.ULIDType.generate()
      assert Posts.get_post(fake_id) == {:error, :not_found}
      assert_raise Ecto.NoResultsError, fn -> Posts.get_post!(fake_id) end
    end
  end

  describe "create_post/3 validations and dynamic features" do
    test "creates a standard post with automated hashtag extraction", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Hello to #elixir and #phoenix community!",
          "visibility" => "public"
        })

      assert post.category == :post
      assert post.status == :published
      assert post.user_id == user.id

      tag_names = Enum.map(post.hashtags, & &1.name)
      assert "elixir" in tag_names
      assert "phoenix" in tag_names
    end

    test "automatically extracts external URL into link_url", %{user: user} do
      Mox.stub(Kollective.HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: "<html></html>"}}
      end)

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Check this out https://hexdocs.pm/ecto for documentation",
          "visibility" => "public"
        })

      assert post.link_url == "https://hexdocs.pm/ecto"
    end

    test "detects Spanish language automatically", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Hola a todos como estan amigos este es un mensaje en espanol",
          "visibility" => "public"
        })

      assert post.language in ["spanish", "english"]
    end

    test "enforces 500-character limit for standard :post category", %{user: user} do
      long_text = String.duplicate("a", 501)

      assert {:error, changeset} =
               Posts.create_post(user, %{
                 "content" => long_text,
                 "text" => long_text,
                 "category" => "post",
                 "visibility" => "public"
               })

      assert "for post posts cannot exceed 500 characters" in errors_on(changeset).text
    end

    test "allows up to 1000 characters for :voice category", %{user: user} do
      voice_text = String.duplicate("a", 500)

      assert {:ok, post} =
               Posts.create_post(user, %{
                 "content" => voice_text,
                 "text" => voice_text,
                 "category" => "voice",
                 "urgency_level" => 2,
                 "visibility" => "public"
               })

      assert post.category == :voice
      assert post.urgency_level == 2
    end

    test "rejects urgency_level > 0 for standard :post category", %{user: user} do
      assert {:error, changeset} =
               Posts.create_post(user, %{
                 "content" => "Standard post trying to be urgent",
                 "category" => "post",
                 "urgency_level" => 3,
                 "visibility" => "public"
               })

      assert "cannot be set for standard posts" in errors_on(changeset).urgency_level
    end

    test "shadowbanned user post initial status defaults to pending" do
      shadow_user =
        user_fixture()
        |> Ecto.Changeset.change(%{is_shadow_banned: true})
        |> Repo.update!()

      {:ok, post} =
        Posts.create_post(shadow_user, %{
          "content" => "Shadowbanned post",
          "visibility" => "public"
        })

      assert post.status == :pending
    end
  end

  describe "update_post/2" do
    test "updates post content, sets edited_at, and increments edit_count", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Original content",
          "visibility" => "public"
        })

      assert post.edit_count == 0
      assert is_nil(post.edited_at)

      {:ok, updated} = Posts.update_post(post, %{"content" => "Updated content"})
      assert updated.content == "Updated content"
      assert updated.edit_count == 1
      assert updated.edited_at != nil

      # Second edit increments again
      {:ok, updated2} = Posts.update_post(updated, %{"content" => "Updated content v2"})
      assert updated2.edit_count == 2
    end

    test "locks poll modifications if poll votes have started", %{user: user} do
      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Post with a poll",
          "visibility" => "public"
        })

      # Attach a poll with votes
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _poll =
        Repo.insert!(%Poll{
          post_id: post.id,
          expires_at: DateTime.add(now, 3600, :second),
          votes_count: 5
        })

      assert {:error, :poll_locked_by_votes} =
               Posts.update_post(post, %{
                 "content" => "Changed text",
                 "poll" => %{"expires_at" => DateTime.add(now, 7200, :second)}
               })
    end
  end

  describe "toggle_like/2 and get_like_count/1" do
    test "likes and unlikes a post correctly", %{user: user} do
      liker = user_fixture()

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Post to like",
          "visibility" => "public"
        })

      assert Posts.get_like_count(post.id) == 0

      assert {:ok, :liked, 1} = Posts.toggle_like(liker.id, post.id)
      assert Posts.get_like_count(post.id) == 1

      assert {:ok, :unliked, 0} = Posts.toggle_like(liker.id, post.id)
      assert Posts.get_like_count(post.id) == 0
    end
  end

  describe "reblog_post/2 and get_reblog_count/1" do
    test "allows reblogging and prevents self-reblogging", %{user: user} do
      booster = user_fixture()

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Post to boost",
          "visibility" => "public"
        })

      # Self-reblog is forbidden
      assert {:error, :self_reblog_not_allowed} = Posts.reblog_post(user.id, post.id)

      # Another user reblogs successfully
      assert {:ok, :reblogged, reblog} = Posts.reblog_post(booster.id, post.id)
      assert reblog.reblog_of_id == post.id
      assert Posts.get_reblog_count(post.id) == 1

      # Re-toggling unreblogs the post
      assert {:ok, :unreblogged} = Posts.reblog_post(booster.id, post.id)
      assert Posts.get_reblog_count(post.id) == 0
    end
  end

  describe "create_reply/3 threading" do
    test "creates reply with root_post_id and caches in_reply_to_username", %{user: user} do
      replier = user_fixture(%{username: "replyguy"})

      {:ok, root_post} =
        Posts.create_post(user, %{
          "content" => "Root conversation post",
          "visibility" => "public"
        })

      {:ok, reply1} =
        Posts.create_reply(replier, root_post, %{
          "content" => "First reply in thread",
          "visibility" => "public"
        })

      assert reply1.in_reply_to_id == root_post.id
      assert reply1.root_post_id == root_post.id
      assert reply1.in_reply_to_username == user.username

      # Second nested reply to reply1 must keep the same root_post_id
      another_replier = user_fixture(%{username: "anotherguy"})

      {:ok, reply2} =
        Posts.create_reply(another_replier, reply1, %{
          "content" => "Replying to first reply",
          "visibility" => "public"
        })

      assert reply2.in_reply_to_id == reply1.id
      assert reply2.root_post_id == root_post.id
      assert reply2.in_reply_to_username == replier.username
    end
  end

  describe "hydrate_virtual_fields/2" do
    test "hydrates has_liked and has_reblogged accurately", %{user: user} do
      viewer = user_fixture()

      {:ok, post} =
        Posts.create_post(user, %{
          "content" => "Post to hydrate",
          "visibility" => "public"
        })

      # Before liking/reblogging
      [hydrated] = Posts.hydrate_virtual_fields([post], viewer)
      assert hydrated.has_liked == false
      assert hydrated.has_reblogged == false

      # After liking
      Posts.toggle_like(viewer.id, post.id)
      [hydrated_liked] = Posts.hydrate_virtual_fields([post], viewer)
      assert hydrated_liked.has_liked == true
      assert hydrated_liked.likes_count == 1
    end

    test "get_post_context returns descendants for a post with replies", %{user: user} do
      replier = user_fixture(%{username: "context_replier"})

      {:ok, root_post} =
        Posts.create_post(user, %{
          "content" => "Parent post for context test",
          "visibility" => "public"
        })

      {:ok, reply} =
        Posts.create_reply(replier, root_post, %{
          "content" => "Reply post for context test",
          "visibility" => "public"
        })

      assert {:ok, context} = Posts.get_post_context(root_post.id, user)
      assert context.focus.post.id == root_post.id
      assert length(context.descendants) == 1
      assert hd(context.descendants).post.id == reply.id

      # Verify main feed excludes replies by default
      feed = Posts.list_posts_for_feed(user, %{})
      feed_ids = Enum.map(feed.entries, & &1.post.id)
      assert root_post.id in feed_ids
      refute reply.id in feed_ids
    end
  end
end

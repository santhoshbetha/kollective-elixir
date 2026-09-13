# test/kollective_web/controllers/post_json_test.exs
defmodule KollectiveWeb.PostJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Posts.Post
  alias Kollective.Accounts.User
  alias KollectiveWeb.PostJSON

  describe "PostJSON serialization" do
    setup do
      author = %User{
        id: "01HXYZPOSTAUTH00000000000",
        username: "post_creator",
        avatar_url: "https://example.com/avatar.png"
      }

      post = %Post{
        id: "01HXYZPOST000000000000000",
        content: "Hello #elixir community! Check this out https://kollective.org",
        category: :post,
        inserted_at: ~U[2026-08-01 10:00:00Z],
        published_at: ~U[2026-08-01 10:05:00Z],
        author: author,
        link_url: "https://kollective.org",
        link_title: "Kollective Platform",
        link_description: "Civic network",
        link_preview_image: "https://kollective.org/og.png",
        attachments: [],
        poll: nil,
        mentions: [%{"id" => "01HXYZMENTION0000000000", "username" => "mentioned_user"}],
        hashtags: [%{name: "elixir"}],
        visibility: "public"
      }

      hydration_item = %{
        post: post,
        likes_count: 12,
        reblogs_count: 4,
        has_liked: true,
        has_reblogged: false
      }

      {:ok, author: author, post: post, item: hydration_item}
    end

    test "show/1 with hydration item serializes metrics and post metadata", %{item: item} do
      data = PostJSON.show(item)

      assert data.id == "01HXYZPOST000000000000000"
      assert data.content =~ "Hello #elixir"
      assert data.likes_count == 12
      assert data.reblogs_count == 4
      assert data.has_liked == true
      assert data.has_reblogged == false
      assert data.author.username == "post_creator"
      assert data.link_preview.title == "Kollective Platform"
      assert [%{name: "elixir", url: _url}] = data.tags
      assert [%{username: "mentioned_user"}] = data.mentions
      assert data.permalink =~ "/posts/01HXYZPOST000000000000000"
    end

    test "show/1 with raw Post struct applies default hydration values", %{post: post} do
      data = PostJSON.show(post)

      assert data.id == "01HXYZPOST000000000000000"
      assert data.likes_count == 0
      assert data.reblogs_count == 0
      assert data.has_liked == false
      assert data.has_reblogged == false
    end

    test "index/1 serializes list of items and handles both wrappers and bare lists", %{
      item: item
    } do
      results1 = PostJSON.index(%{entries: [item]})
      assert length(results1) == 1
      assert hd(results1).id == "01HXYZPOST000000000000000"

      results2 = PostJSON.index([item])
      assert length(results2) == 1
    end

    test "data/1 is an alias for show/1", %{item: item} do
      assert PostJSON.data(item) == PostJSON.show(item)
    end
  end
end

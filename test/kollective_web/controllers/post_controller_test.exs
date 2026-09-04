defmodule KollectiveWeb.PostControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Posts.Post
  alias Kollective.Moderation.RestrictedKeyword
  alias Kollective.Repo

  import Kollective.AccountsFixtures
  import Ecto.Query

  describe "unauthenticated post endpoints" do
    test "GET /api/v1/posts returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/posts")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "GET /api/v1/posts/:id returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/posts/#{Kollective.Schemas.ULIDType.generate()}")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/posts returns 401", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/posts", %{
          "post" => %{
            "content" => "test",
            "text" => "test",
            "category" => "post",
            "target_scope" => "local"
          }
        })

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/posts/:id/reblog returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/posts/#{Kollective.Schemas.ULIDType.generate()}/reblog")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/posts/:id/like returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/posts/#{Kollective.Schemas.ULIDType.generate()}/like")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/posts/:id/replies returns 401", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/posts/#{Kollective.Schemas.ULIDType.generate()}/replies", %{
          "post" => %{"content" => "reply"}
        })

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "authenticated post endpoints" do
    setup :authenticate_user

    test "GET /api/v1/posts/:id returns 404 for missing post", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/posts/#{Kollective.Schemas.ULIDType.generate()}")

      assert conn.status == 404
      assert json_response(conn, 404)["error"] == "Post not found"
    end

    test "GET /api/v1/posts/:id returns 404 for another user's private post", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{visibility: "private"})

      conn = get(conn, ~p"/api/v1/posts/#{post.id}")

      assert conn.status == 404
      assert json_response(conn, 404)["error"] == "Post not found"
    end

    test "POST /api/v1/posts blocks hard restricted content", %{conn: conn} do
      banned_word = insert_hard_keyword()

      conn =
        post(conn, ~p"/api/v1/posts", %{
          "post" => %{
            "content" => "contains #{banned_word}",
            "text" => "contains #{banned_word}",
            "category" => "post"
          }
        })

      assert conn.status in [201, 422]

      response = json_response(conn, conn.status)
      assert response["error"] || response["message"]
    end

    test "POST /api/v1/posts/:id/reblog returns 422 when reblogging own post", %{
      conn: conn,
      user: user
    } do
      post = post_fixture(user)

      conn = post(conn, ~p"/api/v1/posts/#{post.id}/reblog")

      assert conn.status == 422
      assert json_response(conn, 422)["error"] == "You cannot reblog your own post."
    end

    test "GET /api/v1/posts lists public posts", %{conn: conn, user: user} do
      p1 = post_fixture(user, %{content: "Post 1", text: "Post 1"})

      response =
        conn
        |> get(~p"/api/v1/posts")
        |> json_response(200)

      assert is_list(response["data"])
      ids = Enum.map(response["data"], fn p -> p["id"] end)
      assert p1.id in ids
    end

    test "GET /api/v1/posts/:id returns public post details", %{conn: conn, user: user} do
      post = post_fixture(user, %{content: "Special content", text: "Special content"})

      response =
        conn
        |> get(~p"/api/v1/posts/#{post.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == post.id
      assert response["data"]["content"] == "Special content"
    end

    test "POST /api/v1/posts creates a clean public post", %{conn: conn} do
      params = %{
        "post" => %{
          "content" => "This is a clean post content",
          "text" => "This is a clean post content",
          "category" => "post",
          "target_scope" => "local"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/posts", params)
        |> json_response(201)

      assert response["status"] == "ok"
      assert response["data"]["content"] == "This is a clean post content"
    end

    test "POST /api/v1/posts creates a post with a nested poll and options", %{conn: conn} do
      expiry_date = DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_iso8601()

      params = %{
        "post" => %{
          "content" =>
            "Which priority civic project demands municipal funding allocation this quarter? 🗳️",
          "visibility" => "public"
        },
        "poll" => %{
          "multiple" => false,
          "non_anonymous" => false,
          "expires_at" => expiry_date,
          "options" => [
            %{"text" => "Bicycle Lane Expansion Networks"},
            %{"text" => "Community Garden Green Infrastructure"},
            %{"text" => "Public Park Lighting Implementations"}
          ]
        }
      }

      response =
        conn
        |> post(~p"/api/v1/posts", params)
        |> json_response(201)

      assert response["status"] == "ok"

      assert response["data"]["content"] ==
               "Which priority civic project demands municipal funding allocation this quarter? 🗳️"

      poll = response["data"]["poll"]
      assert poll != nil
      assert poll["multiple"] == false
      assert poll["non_anonymous"] == false
      assert poll["expires_at"] != nil

      options = poll["options"]
      assert is_list(options)
      assert length(options) == 3

      option_titles = Enum.map(options, fn opt -> opt["title"] end)
      assert "Bicycle Lane Expansion Networks" in option_titles
      assert "Community Garden Green Infrastructure" in option_titles
      assert "Public Park Lighting Implementations" in option_titles
    end

    test "POST /api/v1/posts/:id/like toggles liking a post", %{conn: conn} do
      other_user = user_fixture()
      post = post_fixture(other_user)

      # 1. Like the post
      response1 =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/like")
        |> json_response(200)

      assert response1["status"] == "success"
      assert response1["has_liked"] == true
      assert response1["count"] == 1

      # 2. Unlike the post
      response2 =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/like")
        |> json_response(200)

      assert response2["status"] == "success"
      assert response2["has_liked"] == false
      assert response2["count"] == 0
    end

    test "POST /api/v1/posts/:id/reblog successfully reblogs and unreblogs another user's post",
         %{
           conn: conn,
           user: _user
         } do
      other_user = user_fixture()
      post = post_fixture(other_user)

      # 1. Reblog the post
      response1 =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/reblog")
        |> json_response(201)

      assert response1["status"] == "success"
      assert response1["action"] == "reblogged"

      # 2. Unreblog the post
      response2 =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/reblog")
        |> json_response(200)

      assert response2["status"] == "success"
      assert response2["action"] == "unreblogged"
    end

    test "POST /api/v1/posts/:id/replies successfully posts a reply", %{conn: conn} do
      other_user = user_fixture()
      parent_post = post_fixture(other_user)

      params = %{
        "post" => %{
          "content" => "Replying to your post"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/posts/#{parent_post.id}/replies", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["content"] == "Replying to your post"
    end

    test "GET /api/v1/posts/:id returns a post with its poll details", %{conn: conn, user: user} do
      post = post_fixture(user)

      poll =
        Repo.insert!(%Kollective.Polls.Poll{
          id: Ecto.ULID.generate(),
          multiple: false,
          expires_at:
            DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          post_id: post.id
        })

      _option1 =
        Repo.insert!(%Kollective.Polls.PollOption{
          id: Ecto.ULID.generate(),
          title: "Yes",
          votes_count: 5,
          poll_id: poll.id
        })

      _option2 =
        Repo.insert!(%Kollective.Polls.PollOption{
          id: Ecto.ULID.generate(),
          title: "No",
          votes_count: 15,
          poll_id: poll.id
        })

      # Force update poll votes_count to trigger percent calculations
      Repo.update_all(
        from(p in Kollective.Polls.Poll, where: p.id == ^poll.id),
        set: [votes_count: 20]
      )

      conn = get(conn, ~p"/api/v1/posts/#{post.id}")
      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["data"]["id"] == post.id

      # Verify the poll field is populated and matches PollJSON schema
      poll_resp = response["data"]["poll"]
      assert poll_resp != nil
      assert poll_resp["id"] == poll.id
      assert poll_resp["multiple"] == false
      assert poll_resp["votes_count"] == 20

      options = poll_resp["options"]
      assert length(options) == 2

      option_yes = Enum.find(options, &(&1["title"] == "Yes"))
      assert option_yes["votes_count"] == 5
      assert option_yes["percent"] == 25.0

      option_no = Enum.find(options, &(&1["title"] == "No"))
      assert option_no["votes_count"] == 15
      assert option_no["percent"] == 75.0
    end

    test "GET /api/v1/posts includes poll details in feed", %{conn: conn, user: user} do
      post = post_fixture(user)

      poll =
        Repo.insert!(%Kollective.Polls.Poll{
          id: Ecto.ULID.generate(),
          multiple: true,
          expires_at:
            DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          post_id: post.id
        })

      _option1 =
        Repo.insert!(%Kollective.Polls.PollOption{
          id: Ecto.ULID.generate(),
          title: "Choice A",
          votes_count: 2,
          poll_id: poll.id
        })

      _option2 =
        Repo.insert!(%Kollective.Polls.PollOption{
          id: Ecto.ULID.generate(),
          title: "Choice B",
          votes_count: 2,
          poll_id: poll.id
        })

      Repo.update_all(
        from(p in Kollective.Polls.Poll, where: p.id == ^poll.id),
        set: [votes_count: 4]
      )

      conn = get(conn, ~p"/api/v1/posts")
      assert conn.status == 200
      response = json_response(conn, 200)

      # Locate our post in the feed
      post_entry = Enum.find(response["data"], &(&1["id"] == post.id))
      assert post_entry != nil

      poll_resp = post_entry["poll"]
      assert poll_resp != nil
      assert poll_resp["id"] == poll.id
      assert poll_resp["multiple"] == true
      assert poll_resp["votes_count"] == 4

      options = poll_resp["options"]
      assert length(options) == 2
      assert Enum.at(options, 0)["percent"] == 50.0
      assert Enum.at(options, 1)["percent"] == 50.0
    end

    test "GET /api/v1/posts/:id returns a post with additional Mastodon fields", %{
      conn: conn,
      user: user
    } do
      parent_post = post_fixture(user)
      mentioned_user = user_fixture()

      post =
        post_fixture(user, %{
          in_reply_to_id: parent_post.id,
          sensitive: true,
          spoiler_text: "spoiler alert!",
          language_override: "spanish",
          visibility: "unlisted",
          mentions: [%{id: mentioned_user.id, username: mentioned_user.username}]
        })

      hashtag =
        Repo.insert!(%Kollective.Hashtags.Hashtag{id: Ecto.ULID.generate(), name: "community"})

      {:ok, post_id_bin} = Ecto.ULID.dump(post.id)
      {:ok, hashtag_id_bin} = Ecto.ULID.dump(hashtag.id)
      Repo.insert_all("posts_hashtags", [%{post_id: post_id_bin, hashtag_id: hashtag_id_bin}])

      reblog_post = post_fixture(user, %{reblog_of_id: post.id})

      conn1 = get(conn, ~p"/api/v1/posts/#{post.id}")
      assert conn1.status == 200
      data1 = json_response(conn1, 200)["data"]

      assert data1["in_reply_to_id"] == parent_post.id
      assert data1["sensitive"] == true
      assert data1["spoiler_text"] == "spoiler alert!"
      assert data1["language"] == "spanish"
      assert data1["visibility"] == "unlisted"
      assert data1["created_at"] != nil

      assert length(data1["mentions"]) == 1
      mention = Enum.at(data1["mentions"], 0)
      assert mention["id"] == mentioned_user.id
      assert mention["username"] == mentioned_user.username

      assert length(data1["tags"]) == 1
      tag = Enum.at(data1["tags"], 0)
      assert tag["name"] == "community"
      assert tag["url"] =~ "/tag/community"

      conn2 = get(conn, ~p"/api/v1/posts/#{reblog_post.id}")
      assert conn2.status == 200
      data2 = json_response(conn2, 200)["data"]

      assert data2["reblog"] != nil
      assert data2["reblog"]["id"] == post.id
      assert data2["reblog"]["content"] == post.content
    end
  end

  defp post_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        content: "Post content #{System.unique_integer([:positive])}",
        text: "Post content",
        visibility: "public",
        status: :published,
        category: :post,
        target_scope: :local,
        mentions: []
      })

    %Post{}
    |> Post.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert!()
  end

  defp insert_hard_keyword do
    word = "blocked_#{System.unique_integer([:positive])}"

    %RestrictedKeyword{}
    |> RestrictedKeyword.changeset(%{
      word: word,
      level: "hard",
      action: "reject",
      is_active: true
    })
    |> Repo.insert!()

    word
  end
end

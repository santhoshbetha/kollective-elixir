# test/kollective_web/controllers/poll_controller_test.exs
defmodule KollectiveWeb.PollControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "show/2 (GET /api/v1/polls/:id)" do
    test "renders poll details successfully when matching record exists", %{conn: conn} do
      # ⚡ Inserts a real poll record into PostgreSQL using a valid Ecto.ULID
      poll = insert(:poll)

      response =
        conn
        |> get(~p"/api/v1/polls/#{poll.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["poll"]["id"] == poll.id
    end

    test "returns 404 not_found when target poll does not exist", %{conn: conn} do
      # ⚡ FIXED: Generates a structurally valid random ULID string to bypass cast crashes safely
      random_ulid = Ecto.ULID.generate()

      response =
        conn
        |> get(~p"/api/v1/polls/#{random_ulid}")
        |> json_response(404)

      assert response["error"] == "Poll not found"
    end
  end

  describe "stream/2 (GET /api/v1/polls/stream)" do
    test "returns list of polls successfully", %{conn: conn} do
      author = insert(:user, country: "US")

      post =
        insert(:post,
          author: author,
          visibility: "public",
          status: :published,
          origin_country: "US"
        )

      _poll = insert(:poll, post: post)

      response =
        conn
        |> get(~p"/api/v1/polls/stream")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["polls"])
      poll_ids = Enum.map(response["polls"], &(&1["id"] || &1[:id]))
      assert post.id in poll_ids
    end

    test "filters polls by category=voice and tab=Voices", %{conn: conn} do
      author = insert(:user, country: "US")

      voice_post =
        insert(:post,
          author: author,
          visibility: "public",
          status: :published,
          category: :voice,
          origin_country: "US"
        )

      insert(:poll, post: voice_post)

      reg_post =
        insert(:post,
          author: author,
          visibility: "public",
          status: :published,
          category: :post,
          origin_country: "US"
        )

      insert(:poll, post: reg_post)

      # 1. category=voice
      res1 =
        conn
        |> get(~p"/api/v1/polls/stream?category=voice")
        |> json_response(200)

      poll_ids1 = Enum.map(res1["polls"], & &1["id"])
      assert voice_post.id in poll_ids1
      refute reg_post.id in poll_ids1

      # 2. tab=Voices
      res2 =
        conn
        |> get(~p"/api/v1/polls/stream?tab=Voices")
        |> json_response(200)

      poll_ids2 = Enum.map(res2["polls"], & &1["id"])
      assert voice_post.id in poll_ids2
      refute reg_post.id in poll_ids2
    end

    test "filters polls by feed=following and tab=Following", %{conn: conn, user: user} do
      friend = insert(:user, country: "US")
      stranger = insert(:user, country: "US")
      insert(:user_relationship, source_id: user.id, target_id: friend.id, type: "follow")

      friend_post =
        insert(:post,
          author: friend,
          visibility: "public",
          status: :published,
          origin_country: "US"
        )

      insert(:poll, post: friend_post)

      stranger_post =
        insert(:post,
          author: stranger,
          visibility: "public",
          status: :published,
          origin_country: "US"
        )

      insert(:poll, post: stranger_post)

      # 1. feed=following
      res1 =
        conn
        |> get(~p"/api/v1/polls/stream?feed=following")
        |> json_response(200)

      poll_ids1 = Enum.map(res1["polls"], & &1["id"])
      assert friend_post.id in poll_ids1
      refute stranger_post.id in poll_ids1

      # 2. tab=Following
      res2 =
        conn
        |> get(~p"/api/v1/polls/stream?tab=Following")
        |> json_response(200)

      poll_ids2 = Enum.map(res2["polls"], & &1["id"])
      assert friend_post.id in poll_ids2
      refute stranger_post.id in poll_ids2
    end

    test "filters polls by geographic scope (world, local)", %{conn: conn, user: user} do
      user =
        Kollective.Repo.update!(
          Ecto.Changeset.change(user, country: "US", state: "CA", county: "Orange")
        )

      conn = assign(conn, :current_user, user)

      # Local poll
      post_local =
        insert(:post,
          visibility: "public",
          status: :published,
          origin_country: "US",
          origin_state: "CA",
          origin_county: "Orange"
        )

      insert(:poll, post: post_local)

      # Foreign poll
      post_world = insert(:post, visibility: "public", status: :published, origin_country: "UK")
      insert(:poll, post: post_world)

      # World scope excludes user's country (US)
      res_world =
        conn
        |> get(~p"/api/v1/polls/stream?scope=world")
        |> json_response(200)

      world_ids = Enum.map(res_world["polls"], & &1["id"])
      assert post_world.id in world_ids
      refute post_local.id in world_ids

      # Local scope matches user's location
      res_local =
        conn
        |> get(~p"/api/v1/polls/stream?scope=local")
        |> json_response(200)

      local_ids = Enum.map(res_local["polls"], & &1["id"])
      assert post_local.id in local_ids
      refute post_world.id in local_ids
    end
  end
end

# test/kollective_web/controllers/post_reaction_controller_test.exs
defmodule KollectiveWeb.PostReactionControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    # Standard JSON API token assignment matching your project baseline
    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "create/2 (POST /api/v1/posts/:post_id/reactions)" do
    setup %{user: user} do
      # Pre-seed a target post row so foreign key constraints clear smoothly
      post = insert(:post, author: user)
      {:ok, post: post}
    end

    test "records a new reaction and broadcasts the timeline addition event", %{
      conn: conn,
      post: post
    } do
      # Subscribe the test process to PubSub to verify live broadcast streaming
      Phoenix.PubSub.subscribe(Kollective.PubSub, "timeline:global")

      params = %{"emoji" => "🔥"}

      response =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/reactions", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "recorded successfully"

      # Assert that the real-time Phoenix PubSub broadcast was dispatched accurately
      assert_receive {:reaction_added, post_id, "🔥"}
      assert post_id == post.id
    end

    test "toggles off and deletes the entry when clicking an identical matching emoji twice", %{
      conn: conn,
      user: user,
      post: post
    } do
      # Pre-seed the reaction to simulate the first click already existing in the database
      insert(:post_reaction, user: user, post: post, emoji: "🔥")

      Phoenix.PubSub.subscribe(Kollective.PubSub, "timeline:global")

      params = %{"emoji" => "🔥"}

      # The second identical post request will trigger your unique index constraint failure fallback block
      response =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/reactions", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "removed successfully"

      # Assert that the real-time removal notification was safely broadcasted instead
      assert_receive {:reaction_removed, post_id, "🔥"}
      assert post_id == post.id

      # Assert that the database row was physically purged from PostgreSQL completely
      refute Kollective.Repo.get_by(Kollective.Posts.PostReaction,
               user_id: user.id,
               post_id: post.id,
               emoji: "🔥"
             )
    end
  end
end

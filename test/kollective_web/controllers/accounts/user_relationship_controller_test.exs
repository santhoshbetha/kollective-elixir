defmodule KollectiveWeb.UserRelationshipControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  setup %{conn: conn} do
    id1 = System.unique_integer([:positive])
    id2 = System.unique_integer([:positive])

    user =
      insert(:user,
        email: "user_rel_#{id1}@test.com",
        username: "user_rel_#{id1}",
        identity_hash: "hash_rel_#{id1}"
      )

    target_user =
      insert(:user,
        email: "target_rel_#{id2}@test.com",
        username: "target_rel_#{id2}",
        identity_hash: "hash_rel_#{id2}",
        is_locked: false
      )

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: authed_conn, user: user, target_user: target_user}
  end

  describe "POST /api/v1/accounts/follow/toggle" do
    test "toggles follow status from not following to following and back", %{
      conn: conn,
      target_user: target_user
    } do
      # 1. First toggle -> Follows
      res1 =
        conn
        |> post(~p"/api/v1/accounts/follow/toggle", %{"target_id" => target_user.id})
        |> json_response(200)

      assert res1["status"] == "following"

      # 2. Second toggle -> Unfollows
      res2 =
        conn
        |> post(~p"/api/v1/accounts/follow/toggle", %{"target_id" => target_user.id})
        |> json_response(200)

      assert res2["status"] == "not_following"
    end

    test "returns requested status when following a locked/private account", %{
      conn: conn
    } do
      id = System.unique_integer([:positive])

      locked_user =
        insert(:user,
          email: "locked_#{id}@test.com",
          username: "locked_#{id}",
          identity_hash: "hash_locked_#{id}",
          is_locked: true
        )

      res =
        conn
        |> post(~p"/api/v1/accounts/follow/toggle", %{"target_id" => locked_user.id})
        |> json_response(200)

      assert res["status"] == "requested"
    end

    test "returns 422 when user tries to follow themselves", %{
      conn: conn,
      user: user
    } do
      res =
        conn
        |> post(~p"/api/v1/accounts/follow/toggle", %{"target_id" => user.id})
        |> json_response(422)

      assert res["error"] =~ "You cannot follow yourself"
    end

    test "returns 422 when target user does not exist", %{conn: conn} do
      fake_id = Ecto.ULID.generate()

      res =
        conn
        |> post(~p"/api/v1/accounts/follow/toggle", %{"target_id" => fake_id})
        |> json_response(422)

      assert res["error"] =~ "User not found"
    end
  end
end

defmodule KollectiveWeb.Admin.ModerationControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Posts.Post

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "admin")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:current_admin, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "reject_post/2" do
    test "rejects an active post and updates status to rejected", %{conn: conn} do
      user = insert(:user)
      post = insert(:post, author: user, status: :published)

      conn =
        post(conn, ~p"/api/v1/admin/posts/#{post.id}/reject", %{"reason" => "Policy violation"})

      assert json_response(conn, 200) == %{
               "status" => "success",
               "data" => %{"id" => post.id, "status" => "rejected"}
             }

      updated_post = Repo.get!(Post, post.id)
      assert updated_post.status == :rejected
      assert updated_post.rejection_reason == "Policy violation"
    end
  end

  describe "appeal_post/2" do
    test "appeals a rejected post and sets status to appealed", %{conn: conn} do
      user = insert(:user)
      post = insert(:post, author: user, status: :rejected, rejection_reason: "Initial flag")

      conn =
        post(conn, ~p"/api/v1/admin/posts/#{post.id}/appeal", %{
          "reason" => "User appealed policy flag"
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "data" => %{"id" => post.id, "status" => "appealed"}
             }

      updated_post = Repo.get!(Post, post.id)
      assert updated_post.status == :appealed
    end
  end

  describe "restore_post/2" do
    test "restores a rejected post back to published status", %{conn: conn} do
      user = insert(:user)
      post = insert(:post, author: user, status: :rejected, rejection_reason: "Automated flag")

      conn = post(conn, ~p"/api/v1/admin/posts/#{post.id}/restore")

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" => "Content successfully restored to public feeds."
             }

      updated_post = Repo.get!(Post, post.id)
      assert updated_post.status == :published
      assert is_nil(updated_post.rejected_at)
    end
  end

  describe "kill_post/2" do
    test "hard purges post content from database", %{conn: conn} do
      user = insert(:user)
      post = insert(:post, author: user)

      conn = delete(conn, ~p"/api/v1/admin/posts/#{post.id}/kill")

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" => "Content hard-purged from system timelines."
             }

      assert Repo.get(Post, post.id) == nil
    end
  end

  describe "bulk_approve/2" do
    test "returns bad_request when moderation queue is empty", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/admin/posts/bulk_approve", %{"params" => %{}})

      assert json_response(conn, 400) == %{
               "error" => "There are no pending moderation items to approve."
             }
    end
  end
end

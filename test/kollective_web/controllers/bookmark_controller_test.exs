# test/kollective_web/controllers/bookmark_controller_test.exs
defmodule KollectiveWeb.BookmarkControllerTest do
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

  describe "index/2 (GET /api/v1/bookmarks)" do
    test "lists all bookmarked posts for the current user", %{conn: conn, user: user} do
      author = insert(:user)
      post1 = insert(:post, author: author)
      post2 = insert(:post, author: author)

      insert(:post_bookmark, user: user, post: post1)
      insert(:post_bookmark, user: user, post: post2)

      response =
        conn
        |> get(~p"/api/v1/bookmarks")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert length(response["data"]) == 2
    end

    test "multi-user isolation: user only sees their own bookmarks", %{conn: conn, user: _user} do
      other_user = insert(:user)
      author = insert(:user)
      post1 = insert(:post, author: author)
      post2 = insert(:post, author: author)

      insert(:post_bookmark, user: other_user, post: post1)
      insert(:post_bookmark, user: other_user, post: post2)

      response =
        conn
        |> get(~p"/api/v1/bookmarks")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"] == []
    end
  end

  describe "toggle/2 (POST /api/v1/posts/:post_id/bookmark)" do
    setup do
      author = insert(:user)
      post = insert(:post, author: author)
      {:ok, post: post}
    end

    test "bookmarks a post on first click (inserted)", %{conn: conn, post: post} do
      response =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/bookmark")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "inserted"
      assert response["message"] == "Post successfully bookmarked."
    end

    test "removes bookmark on second click (removed)", %{conn: conn, user: user, post: post} do
      insert(:post_bookmark, user: user, post: post)

      response =
        conn
        |> post(~p"/api/v1/posts/#{post.id}/bookmark")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "removed"
      assert response["message"] == "Bookmark successfully removed."
    end
  end

  describe "delete/2 (DELETE /api/v1/bookmarks/:bookmark_id)" do
    setup %{user: user} do
      author = insert(:user)
      post = insert(:post, author: author)
      bookmark = insert(:post_bookmark, user: user, post: post)
      {:ok, post: post, bookmark: bookmark}
    end

    test "deletes a bookmark by bookmark_id", %{conn: conn, bookmark: bookmark} do
      response =
        conn
        |> delete(~p"/api/v1/bookmarks/#{bookmark.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "deleted"
      assert response["message"] == "Bookmark successfully removed."
    end

    test "deletes a bookmark by post_id via /api/v1/posts/:post_id/bookmark", %{
      conn: conn,
      post: post
    } do
      response =
        conn
        |> delete(~p"/api/v1/posts/#{post.id}/bookmark")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["action"] == "deleted"
      assert response["message"] == "Bookmark successfully removed."
    end

    test "returns 404 when trying to delete a non-existent bookmark", %{conn: conn} do
      fake_id = Ecto.ULID.generate()

      response =
        conn
        |> delete(~p"/api/v1/bookmarks/#{fake_id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["message"] == "Bookmark not found."
    end
  end
end

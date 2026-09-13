# test/kollective_web/controllers/comment_json_test.exs
defmodule KollectiveWeb.CommentJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.User
  alias KollectiveWeb.CommentJSON

  describe "CommentJSON serialization" do
    test "data/1 serializes comment with author, timestamps, and replies" do
      user = %User{
        id: "01HXYZUSER00000000000000",
        username: "commenter_jane",
        avatar_url: "https://example.com/jane.jpg"
      }

      reply_comment = %{
        id: "01HXYZREPLY0000000000000",
        content: "I agree with this!",
        user: user,
        inserted_at: ~U[2026-08-01 11:30:00Z],
        parent_id: "01HXYZCOMM00000000000000",
        replies: []
      }

      root_comment = %{
        id: "01HXYZCOMM00000000000000",
        content: "Root comment text",
        user: user,
        inserted_at: ~U[2026-08-01 11:00:00Z],
        likes_count: 5,
        has_liked: true,
        parent_id: nil,
        replies: [reply_comment]
      }

      data = CommentJSON.data(root_comment)

      assert data.id == "01HXYZCOMM00000000000000"
      assert data.content == "Root comment text"
      assert data.likes_count == 5
      assert data.has_liked == true
      assert data.parent_id == nil
      assert data.author.username == "commenter_jane"
      assert length(data.replies) == 1

      [nested_reply] = data.replies
      assert nested_reply.id == "01HXYZREPLY0000000000000"
      assert nested_reply.content == "I agree with this!"
      assert nested_reply.parent_id == "01HXYZCOMM00000000000000"
    end

    test "data/1 handles missing user association gracefully" do
      comment = %{
        id: "01HXYZCOMM00000000000001",
        content: "Orphan comment",
        user: nil,
        inserted_at: ~U[2026-08-01 11:00:00Z],
        parent_id: nil,
        replies: []
      }

      data = CommentJSON.data(comment)
      assert data.author == nil
    end

    test "index/1 and show/1 wrap comments properly" do
      comment = %{
        id: "01HXYZCOMM00000000000002",
        content: "Test",
        inserted_at: ~U[2026-08-01 11:00:00Z],
        parent_id: nil,
        replies: []
      }

      show_res = CommentJSON.show(%{comment: comment})
      assert show_res.data.id == "01HXYZCOMM00000000000002"

      index_res = CommentJSON.index([comment])
      assert length(index_res) == 1
    end
  end
end

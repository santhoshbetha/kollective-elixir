defmodule KollectiveWeb.EventCommentControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  alias Kollective.Repo

  setup :authenticate_user

  setup %{conn: conn, user: user} do
    # Create an event to comment on
    event = insert(:event)

    {:ok, conn: conn, user: user, event: event}
  end

  describe "GET /api/v1/event_comments" do
    test "lists approved top-level comments for an event", %{conn: conn, event: event} do
      # Create approved comments
      c1 = insert(:comment, event: event, moderation_status: "approved")
      c2 = insert(:comment, event: event, moderation_status: "approved")
      # Create an unapproved/pending comment (should not be listed)
      _pending = insert(:comment, event: event, moderation_status: "pending")
      # Create a reply comment (should not be listed in top-level)
      _reply = insert(:comment, event: event, parent: c1, moderation_status: "approved")

      response =
        conn
        |> get(~p"/api/v1/event_comments", %{"event_id" => event.id})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])

      ids = Enum.map(response["data"], fn c -> c["id"] end)
      assert to_string(c1.id) in ids
      assert to_string(c2.id) in ids
      refute to_string(_reply.id) in ids
    end

    test "handles keyset pagination cursor", %{conn: conn, event: event} do
      _c1 = insert(:comment, event: event, moderation_status: "approved")
      _c2 = insert(:comment, event: event, moderation_status: "approved")

      response =
        conn
        |> get(~p"/api/v1/event_comments", %{"event_id" => event.id, "limit" => 1})
        |> json_response(200)

      assert response["status"] == "success"
      assert length(response["data"]) == 1
      assert response["next_cursor"]
    end
  end

  describe "GET /api/v1/event_comments/:id" do
    test "shows approved comment details", %{conn: conn, event: event} do
      comment = insert(:comment, event: event, moderation_status: "approved")

      response =
        conn
        |> get(~p"/api/v1/event_comments/#{comment.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == to_string(comment.id)
    end

    test "returns 404 for unapproved comment", %{conn: conn, event: event} do
      comment = insert(:comment, event: event, moderation_status: "pending")

      response =
        conn
        |> get(~p"/api/v1/event_comments/#{comment.id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["error"] =~ "Comment not found"
    end
  end

  describe "POST /api/v1/events_comments/:event_id/comment" do
    test "successfully posts a comment with valid parameters", %{conn: conn, event: event} do
      params = %{
        "comment" => %{
          "content" => "I'll be there!"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/events_comments/#{event.id}/comment", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["content"] == "I'll be there!"
      assert response["data"]["moderation_status"] == "approved"
    end

    test "returns 422 if comment is empty (no content and no image)", %{conn: conn, event: event} do
      params = %{
        "comment" => %{
          "content" => ""
        }
      }

      response =
        conn
        |> post(~p"/api/v1/events_comments/#{event.id}/comment", params)
        |> json_response(422)

      assert response["error"] =~ "Failed to create comment"
    end

    test "soft bans comment (sets status pending) if user is shadow banned", %{
      conn: conn,
      event: event,
      user: user
    } do
      user = user |> Ecto.Changeset.change(%{is_shadow_banned: true}) |> Repo.update!()
      conn = assign(conn, :current_user, user)

      params = %{
        "comment" => %{
          "content" => "Normal safe comment but from shadow banned user"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/events_comments/#{event.id}/comment", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["moderation_status"] == "pending"
    end

    test "rejects comment with 422 if it contains forbidden content (hard banned)", %{
      conn: conn,
      event: event
    } do
      Repo.insert!(%Kollective.Moderation.RestrictedKeyword{
        word: "spammyword",
        level: "hard",
        action: "reject"
      })

      params = %{
        "comment" => %{
          "content" => "This has a spammyword in it"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/events_comments/#{event.id}/comment", params)
        |> json_response(422)

      assert response["error"] =~ "contains prohibited language"
    end

    test "cooldown ban trigger workflow on multiple hard-banned words attempts", %{
      conn: conn,
      event: event,
      user: user
    } do
      Repo.insert!(%Kollective.Moderation.RestrictedKeyword{
        word: "spammyword",
        level: "hard",
        action: "reject"
      })

      # Record one denial to consume the allow limit, making the next call trigger cooldown
      Kollective.Moderation.Moderation.record_denial(user.id)
      Kollective.Moderation.Moderation.track_denied_word(user.id, "spammyword")

      params = %{
        "comment" => %{
          "content" => "Second strike spammyword attempt"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/events_comments/#{event.id}/comment", params)
        |> json_response(200)

      # Tricked code returns success message to bots
      assert response["status"] == "success"
      assert response["message"] =~ "Comment queued for review"
    end
  end

  describe "POST /api/v1/event_comments/:comment_id/like" do
    test "successfully likes a comment", %{conn: conn, event: event} do
      comment = insert(:comment, event: event, moderation_status: "approved")

      response =
        conn
        |> post(~p"/api/v1/event_comments/#{comment.id}/like")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "liked successfully"
    end

    test "returns conflict status 409 if already liked", %{conn: conn, event: event, user: user} do
      comment = insert(:comment, event: event, moderation_status: "approved")

      Repo.insert!(%Kollective.Events.CommentLike{user_id: user.id, comment_id: comment.id})

      response =
        conn
        |> post(~p"/api/v1/event_comments/#{comment.id}/like")
        |> json_response(409)

      assert response["error"] == "already_liked"
    end
  end

  describe "GET /api/v1/event_comments/image/presign" do
    test "generates a presigned asset upload URL", %{conn: conn} do
      response =
        conn
        |> get(~p"/api/v1/event_comments/image/presign", %{"content_type" => "image/png"})
        |> json_response(200)

      assert response["status"] == "success"
      assert response["upload_url"]
      assert response["final_asset_url"]
    end
  end
end

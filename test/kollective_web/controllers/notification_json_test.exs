defmodule KollectiveWeb.NotificationJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.User
  alias Kollective.Notifications.Notification
  alias KollectiveWeb.NotificationJSON

  describe "NotificationJSON serialization" do
    setup do
      actor = %User{
        id: "01HXYZACTOR000000000000",
        username: "actor_bob",
        avatar_url: "https://example.com/bob.jpg"
      }

      notification = %Notification{
        id: "01HXYZNOTIF000000000000",
        type: "reply",
        read: false,
        metadata: %{"preview" => "replied to your post"},
        target_id: "01HXYZPOST000000000000",
        target_type: "Post",
        actor: actor,
        inserted_at: ~U[2026-08-01 12:00:00Z]
      }

      {:ok, actor: actor, notification: notification}
    end

    test "data/1 formats notification with actor and target", %{notification: notification} do
      data = NotificationJSON.data(notification)

      assert data.id == "01HXYZNOTIF000000000000"
      assert data.type == "reply"
      assert data.is_read == false
      assert data.preview_text == "replied to your post"
      assert data.inserted_at == "2026-08-01T12:00:00Z"
      assert data.actor.id == "01HXYZACTOR000000000000"
      assert data.actor.username == "actor_bob"
      assert data.actor.avatar_url == "https://example.com/bob.jpg"
      assert data.target.id == "01HXYZPOST000000000000"
      assert data.target.type == "Post"
    end

    test "data/1 handles missing actor and empty metadata gracefully", %{
      notification: notification
    } do
      bare_notification = %{
        notification
        | actor: nil,
          metadata: nil
      }

      data = NotificationJSON.data(bare_notification)

      assert data.actor == nil
      assert data.preview_text == "interacted with your profile."
    end

    test "index/1 serializes list of notifications", %{notification: notification} do
      items = NotificationJSON.index(%{notifications: [notification]})

      assert is_list(items)
      assert length(items) == 1
      assert hd(items).id == "01HXYZNOTIF000000000000"

      items_list = NotificationJSON.index([notification])
      assert length(items_list) == 1
    end

    test "show/1 formats single notification wrapped in data", %{notification: notification} do
      result = NotificationJSON.show(%{notification: notification})
      assert result.data.id == "01HXYZNOTIF000000000000"

      result_bare = NotificationJSON.show(notification)
      assert result_bare.data.id == "01HXYZNOTIF000000000000"
    end

    test "unread_count/1 formats count payload" do
      result = NotificationJSON.unread_count(5)
      assert result.status == "success"
      assert result.count == 5
    end

    test "marked_as_read/1 formats count message" do
      result = NotificationJSON.marked_as_read(3)
      assert result.status == "success"
      assert result.message == "3 notifications marked as read"
    end
  end
end

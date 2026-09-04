defmodule Kollective.Notifications.NotificationsTest do
  use Kollective.DataCase, async: true

  import Kollective.Factory
  alias Kollective.Notifications.Notifications
  alias Kollective.Notifications.Notification

  setup do
    user = insert(:user)
    actor = insert(:user)

    {:ok, user: user, actor: actor}
  end

  describe "notify/5" do
    test "successfully persists a notification and triggers real-time buffers", %{
      user: user,
      actor: actor
    } do
      post = insert(:post, author: actor)

      assert {:ok, %Notification{} = notification} =
               Notifications.notify(user.id, actor.id, "mention", %{
                 post_id: post.id,
                 target_id: post.id,
                 target_type: "Post"
               })

      assert notification.user_id == user.id
      assert notification.actor_id == actor.id
      assert notification.type == "mention"
      assert notification.target_id == post.id
    end

    test "respects self-notification guard when IDs are represented as string and binary mixtures",
         %{
           user: user
         } do
      # Pass recipient as binary ULID and actor as string representation of the same user
      recipient_id = user.id
      actor_id = to_string(user.id)

      assert {:error, :muted_or_self_action} =
               Notifications.notify(recipient_id, actor_id, "mention", %{})
    end

    test "skips delivery if recipient has muted the actor", %{user: user, actor: actor} do
      # Insert notification_mute relationship
      insert(:user_relationship,
        source_id: user.id,
        target_id: actor.id,
        type: "notification_mute"
      )

      assert {:error, :muted_or_self_action} =
               Notifications.notify(user.id, actor.id, "mention", %{})
    end

    test "safely skips Oban buffer enqueueing when target_id is nil", %{user: user, actor: actor} do
      # Notifications without target_id should not crash
      assert {:ok, %Notification{} = notification} =
               Notifications.notify(user.id, actor.id, "follow", %{
                 target_id: nil,
                 target_type: "User"
               })

      assert is_nil(notification.target_id)
    end
  end

  describe "notify_reply/3" do
    test "delivers notification if thread is not muted", %{user: user, actor: actor} do
      post = insert(:post, author: user)
      reply = insert(:post, author: actor, in_reply_to_id: post.id, root_post_id: post.id)

      assert {:ok, %Notification{} = notification} =
               Notifications.notify_reply(user.id, actor.id, reply)

      assert notification.user_id == user.id
      assert notification.actor_id == actor.id
      assert notification.type == "reply"
      assert notification.target_id == reply.id
    end

    test "does not deliver notification if thread is muted by recipient", %{
      user: user,
      actor: actor
    } do
      post = insert(:post, author: user)
      reply = insert(:post, author: actor, in_reply_to_id: post.id, root_post_id: post.id)

      # Mute the thread
      Kollective.Repo.insert!(%Kollective.Posts.ThreadMute{
        user_id: user.id,
        root_post_id: post.id
      })

      assert {:error, :thread_silenced_or_self} =
               Notifications.notify_reply(user.id, actor.id, reply)
    end
  end

  describe "list_grouped_notifications/1" do
    test "correctly groups non-consecutive notification items by type and target", %{
      user: user,
      actor: actor
    } do
      actor2 = insert(:user)
      post1 = insert(:post, author: user)
      post2 = insert(:post, author: user)

      # Insert interleaved (non-consecutive) notifications
      # 1. actor likes post1
      # 2. actor2 likes post2
      # 3. actor2 likes post1
      insert(:notification,
        user: user,
        actor: actor,
        type: "favourite",
        target_id: post1.id,
        post_id: post1.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-10, :second)
      )

      insert(:notification,
        user: user,
        actor: actor2,
        type: "favourite",
        target_id: post2.id,
        post_id: post2.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-5, :second)
      )

      insert(:notification,
        user: user,
        actor: actor2,
        type: "favourite",
        target_id: post1.id,
        post_id: post1.id,
        inserted_at: DateTime.utc_now()
      )

      grouped = Notifications.list_grouped_notifications(user.id)

      # Should produce exactly 2 grouped items (one for post1, one for post2)
      assert length(grouped) == 2

      # Verify grouping for post1 (which has 2 likes: actor and actor2)
      post1_group =
        Enum.find(grouped, fn
          %Notification{} -> false
          map -> map.type == "favourite" and map.post.id == post1.id
        end)

      assert post1_group
      assert post1_group.count == 2

      # Verify grouping for post2 (which has 1 like: actor2)
      post2_single =
        Enum.find(grouped, fn
          %Notification{} = n -> n.target_id == post2.id
          _map -> false
        end)

      assert post2_single
    end
  end
end

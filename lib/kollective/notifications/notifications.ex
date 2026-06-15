defmodule Kollective.Notifications.Notifications do
  alias Kollective.Repo
  import Ecto.Query
  alias Kollective.Notifications.Notification
  alias KollectiveWeb.Endpoint
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Posts.ThreadMute

   # Example usage:

  def create_action_notification(user_id, actor_id, post_id \\ nil, type) do
    %Notification{}
    |> Notification.changeset(%{
        user_id: user_id,
        actor_id: actor_id,
        post_id: post_id,
        type: type
      })
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        broadcast_action_notification(notification)
        {:ok, notification}
      error -> error
    end
  end

  defp broadcast_action_notification(n) do
    # Preload the actor to show "John Doe wants to follow you"
    n = Repo.preload(n, :actor)

    topic = "notifications:#{n.user_id}"
    payload = %{
      id: n.id,
      type: n.type,
      actor_username: n.actor.username,
      post_id: n.post_id,
      inserted_at: n.inserted_at
    }

    Endpoint.broadcast(topic, "new_notification", payload)
  end

  def mark_all_as_read(user_id) do
    from(n in Notification, where: n.user_id == ^user_id and n.read == false)
    |> Repo.update_all(set: [read: true, updated_at: NaiveDateTime.utc_now()])
  end

  #The Grouping Logic
  # When fetching notifications for the UI, we use group_by or a Virtual Field in Elixir to consolidate them.
  def list_grouped_notifications(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> preload(:actor)
    |> Repo.all()
    |> Enum.chunk_by(fn n -> {n.type, n.target_id} end) # Group identical actions on the same target
    |> Enum.map(&summarize_group/1)
  end

  defp summarize_group([first | _rest] = group) when length(group) > 1 do
    %{
      id: first.id,
      type: first.type,
      latest_actor: first.actor,
      count: length(group),
      text: "#{first.actor.username} and #{length(group) - 1} others #{action_text(first.type)}",
      inserted_at: first.inserted_at
    }
  end

  defp summarize_group([single]), do: single

  defp action_text("like"), do: "liked your post"
  defp action_text("follow"), do: "followed you"

  # Real-time "Debouncing" (Advanced)
  # To avoid spamming Phoenix Channels, you can "debounce" notifications. If 5 people like a post in 10 seconds,
  # you only send one broadcast to the channel saying "5 people liked your post."

  # When someone follows a user, you just call:
  # Kollective.Notifications.notify_with_debounce(target_id, source_id, "follow_request", target_id, "User")
  def notify_with_debounce(user_id, actor_id, type, target_id, target_type) do
    # 1. Logic to check if we should "debounce" (optional)
    # e.g., don't create a new row if a similar notification happened 5 seconds ago

    # 2. Persist to DB using your ULID logic
    case create_action_object_notification(user_id, actor_id, type, target_id, target_type) do
      {:ok, notification} ->
        # 3. Push real-time update
        # broadcast_action_object_notification(notification)
        # 2. Send to buffer for the real-time ping
        # This prevents the "ping-ping-ping" spam
        Kollective.Notifications.Buffer.enqueue(user_id, type, target_id)
        {:ok, notification}

      error -> error
    end
  end

  # Private helper for DB insertion
  defp create_action_object_notification(user_id, actor_id, type, target_id, target_type) do
    %Notification{}
    |> Notification.changeset(%{
      user_id: user_id,
      actor_id: actor_id,
      type: type,
      target_id: target_id,
      target_type: target_type
    })
    |> Repo.insert()
  end

  # Private helper for Channel broadcasting
  #defp broadcast_action_object_notification(n) do
  #  topic = "notifications:#{n.user_id}"
  #  Endpoint.broadcast(topic, "new_notification", %{
  #    id: n.id,
  #    type: n.type,
  #    target_id: n.target_id,
  #    target_type: n.target_type
  #  })
  #end

  # Notification Muting
  # The Filter Logic (The "Silencer")
  # To make this effective, you must update your notification logic to check for this relationship
  # before broadcasting or saving
  def notify(target_user_id, actor_id, type, data) do
    # CHECK: Has the target muted notifications from this actor?
    is_muted = Repo.exists?(
      from r in UserRelationship,
        where: r.source_id == ^target_user_id and
              r.target_id == ^actor_id and
              r.type == "notification_mute"
    )

    unless is_muted do
      # 1. Save to DB for the 'Notifications' tab
      create_action_notification(target_user_id, actor_id, type)

      # 2. Broadcast real-time via Phoenix Channels
      KollectiveWeb.Endpoint.broadcast("notifications:#{target_user_id}", "new_#{type}", data)
    end
  end

  # list_notifications query to show a user their full history of follows, mentions, and reblogs
  # This query fetches the notifications for a specific user, preloads
  # the person who triggered it, and includes the post content if applicable
  def list_notifications(user_id, params \\ %{}) do
    cursor = params["cursor"]
    limit = 20

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        # Join the "actor" (the person who followed/liked/mentioned)
        preload: [:actor],
        # Join the "post" (if it's a mention or reblog)
        preload: [:post],
        order_by: [desc: n.inserted_at],
        limit: ^limit

    # Handle infinite scroll pagination
    query = if cursor, do: where(query, [n], n.id < ^cursor), else: query

    notifications = Repo.all(query)

    %{
      notifications: notifications,
      next_cursor: List.last(notifications) && List.last(notifications).id
    }
  end

  #Thread Muting (also known as Conversation Muting in Mastodon), you allow a user to silence all

  #, update your global notify logic. Before saving a notification or broadcasting
  #via Phoenix Channels, check if the user has muted the entire thread
  #When someone replies to a post, your notification system needs to check if the author of the original
  #post (the person being replied to) has muted that thread.
  def notify_reply(recipient_id, actor_id, post) do
    # Find the head of this specific conversation
    root_id = post.root_post_id || post.id

    # Check if the recipient has muted this thread
    is_muted = Repo.exists?(
      from tm in ThreadMute,
        where: tm.user_id == ^recipient_id and tm.root_post_id == ^root_id
    )

    unless is_muted do
      # 1. Save Notification to DB
      # 2. Broadcast via Phoenix Channel (notifications:recipient_id)
      send_realtime_notification(recipient_id, actor_id, post)
    end
  end

  def send_realtime_notification(recipient_id, actor_id, post) do
    # 1. Fetch the actor's name to show in the React toast
    # 1. THE "SELF-NOTIFICATION" GUARD
    if recipient_id != actor_id do
      actor = Kollective.Accounts.Accounts.get_user!(actor_id)

      # 2. Define the topic based on the recipient's ID
      topic = "notifications:#{recipient_id}"

      # 3. Define the event name (React will listen for this)
      event = "new_notification"

      # 4. Construct the payload
      payload = %{
        actor_name: actor.username,
        actor_avatar: actor.avatar_url,
        post_id: post.id,
        type: determine_type(post), # "reply", "reblog", etc.
        # Send a small snippet of the content for the preview
        preview: String.slice(post.content || "", 0, 40) <> "..."
      }

      # 5. Broadcast to the Phoenix Channel
      Endpoint.broadcast(topic, event, payload)
    end
  end

  defp determine_type(post) do
    cond do
      post.reblog_of_id -> "reblog"
      post.in_reply_to_id -> "reply"
      true -> "mention"
    end
  end

  #"Read Status" so that the notification badge in React disappears once the user opens their notifications tab
  def count_unread_notifications(user_id) do
    Notification

    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> Repo.aggregate(:count, :id)
  end

  def mark_all_as_read2(user_id) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Notification

    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now])
  end

end

defmodule Kollective.Notifications.Notifications do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Notifications.Notification
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Posts.Post

  # Mock placeholder if ThreadMute module isn't loaded; replace with your actual module path
  # alias Kollective.Posts.ThreadMute

  # ─── SECTION 1: DELIVER & PERSIST ENGINES (With Safety Guards & Silencers) ───

  @doc """
  Main dispatch controller for general notifications. Automatically intercepts
  and checks user 'notification_mute' rules before executing database inserts or socket broadcasts.
  """
  def notify(target_user_id, actor_id, type, attrs \\ %{}, data_payload \\ %{}) do
    target_user_id = cast_ulid(target_user_id)
    actor_id = cast_ulid(actor_id)

    # 1. THE "SILENCER": Has the recipient muted notifications from this specific actor?
    is_muted =
      Repo.exists?(
        from r in UserRelationship,
          where:
            r.source_id == ^target_user_id and r.target_id == ^actor_id and
              r.type == "notification_mute"
      )

    # 2. SELF-NOTIFICATION GUARD: Don't notify users of their own actions
    if not is_muted and target_user_id != actor_id do
      # Merge base relational tracking fields
      full_attrs =
        attrs
        |> Map.put(:user_id, target_user_id)
        |> Map.put(:actor_id, actor_id)
        |> Map.put(:type, type)

      # Persist to DB using your ULID logic
      case create_action_object_notification(full_attrs) do
        {:ok, notification} ->
          # Route cleanly to your high-performance frontend buffering queue

          # Real-time "Debouncing" (Advanced)
          # To avoid spamming Phoenix Channels, you can "debounce" notifications. If 5 people like a post in 10 seconds,
          # you only send one broadcast to the channel saying "5 people liked your post."
          if notification.target_id do
            Kollective.Notifications.Buffer.enqueue(target_user_id, type, notification.target_id)
          end

          # Fire immediate WebSocket to push the toast popup payload
          broadcast_raw_toast(
            target_user_id,
            type,
            Map.put(data_payload, :actor_id, actor_id)
          )

          {:ok, notification}

        error ->
          error
      end
    else
      {:error, :muted_or_self_action}
    end
  end

  defp cast_ulid(nil), do: nil

  defp cast_ulid(binary) when is_binary(binary) and byte_size(binary) == 26,
    do: Ecto.ULID.cast!(binary)

  defp cast_ulid(val), do: val

  # Thread Muting (also known as Conversation Muting in Mastodon), you allow a user to silence all
  # , update your global notify logic. Before saving a notification or broadcasting
  # via Phoenix Channels, check if the user has muted the entire thread
  # When someone replies to a post, your notification system needs to check if the author of the original
  # post (the person being replied to) has muted that thread.

  @doc """
  Thread/Conversation Muting Router. Verifies if the recipient has silenced the
  root thread context before delivering reply notification alerts.
  """
  def notify_reply(recipient_id, actor_id, %Post{} = post) do
    root_id = post.root_post_id || post.id

    is_thread_muted =
      Repo.exists?(
        from tm in Kollective.Posts.ThreadMute,
          where: tm.user_id == ^recipient_id and tm.root_post_id == ^root_id
      )

    if not is_thread_muted and recipient_id != actor_id do
      # "reply", "reblog", etc.
      type = determine_type(post)

      # Build the notification properties
      attrs = %{
        post_id: post.id,
        target_id: post.id,
        target_type: "Post",
        metadata: %{preview: String.slice(post.content || "", 0, 40) <> "..."}
      }

      # Reuse your primary notify engine to catch relationship locks automatically
      notify(recipient_id, actor_id, type, attrs, %{
        post_id: post.id,
        preview: String.slice(post.content || "", 0, 40) <> "..."
      })
    else
      {:error, :thread_silenced_or_self}
    end
  end

  # Private DB Insertion Routines
  def create_action_object_notification(attrs) do
    # ⚡ FIXED: Cast any potential loose text strings into strict 16-byte binaries
    # before passing them to the insert pipeline
    attrs =
      attrs
      |> cast_ulid_key(:target_id)
      |> cast_ulid_key(:post_id)
      |> cast_ulid_key(:event_id)

    %Kollective.Notifications.Notification{}
    |> Kollective.Notifications.Notification.changeset(attrs)
    |> Kollective.Repo.insert()
  end

  # Private helper to safely convert incoming text variables
  defp cast_ulid_key(attrs, key) do
    case Map.get(attrs, key) do
      binary when is_binary(binary) and byte_size(binary) == 26 ->
        Map.put(attrs, key, Ecto.ULID.cast!(binary))

      _ ->
        attrs
    end
  end

  # ─── SECTION 2: READ & LIST RETRIEVALS (Infinite Scroll + RAM Grouping) ───

  # list_notifications query to show a user their full history of follows, mentions, and reblogs
  # This query fetches the notifications for a specific user, preloads
  # the person who triggered it, and includes the post content if applicable

  @doc """
  Fetches paginated notification rows using optimized keyset cursor parameters.
  Returns %{notifications: [...], next_cursor: id_or_nil}.
  """
  def list_notifications(user_id, params \\ %{}) do
    cursor = params["cursor"] || params["max_id"]
    limit = 20

    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        preload: [:actor, :post, :event],
        # Keyset sorting matching sequential ULIDs/IDs
        order_by: [desc: n.id],
        limit: ^limit

    query = if cursor && cursor != "", do: where(query, [n], n.id < ^cursor), else: query

    notifications = Repo.all(query)
    next_cursor = if List.last(notifications), do: List.last(notifications).id, else: nil

    %{
      notifications: notifications,
      next_cursor: next_cursor
    }
  end

  def list_grouped_notifications(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> preload([:actor, :post])
    |> Repo.all()
    # Group identically-typed actions mapping to the same target node footprint
    |> Enum.group_by(fn n -> {n.type, n.target_id} end)
    |> Map.values()
    |> Enum.map(&summarize_group/1)
    |> Enum.sort_by(
      fn
        %Notification{} = n -> n.inserted_at
        %{} = map -> map.inserted_at
      end,
      {:desc, DateTime}
    )
  end

  defp summarize_group([first | _rest] = group) when length(group) > 1 do
    %{
      id: first.id,
      type: first.type,
      latest_actor: first.actor,
      post: first.post,
      count: length(group),
      text: "#{first.actor.username} and #{length(group) - 1} others #{action_text(first.type)}",
      inserted_at: first.inserted_at
    }
  end

  defp summarize_group([single]), do: single

  # --- Aggregate Unread State Management Toggles ---

  # "Read Status" so that the notification badge in React disappears once the user opens their notifications tab
  def count_unread_notifications(user_id) do
    from(n in Notification, where: n.user_id == ^user_id and n.read == false)
    |> Repo.aggregate(:count, :id)
  end

  def mark_all_as_read(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(n in Notification, where: n.user_id == ^user_id and n.read == false)
    |> Repo.update_all(set: [read: true, updated_at: now])
  end

  # ─── SECTION 3: TRANSIENT STREAM ROUTERS (RAM-Only WebSocket Channels) ───

  defp broadcast_raw_toast(recipient_id, type, data) do
    topic = "user_notifications:#{recipient_id}"

    # Pre-hydrate actor data manually to help React render details inside Toast elements instantly
    actor = Accounts.get_user!(data[:actor_id] || data["actor_id"])

    payload = %{
      type: type,
      actor_name: actor.username,
      actor_avatar: actor.avatar_url,
      post_id: data[:post_id] || data["post_id"],
      preview: data[:preview] || ""
    }

    KollectiveWeb.Endpoint.broadcast(topic, "new_notification", payload)
  end

  defp determine_type(post) do
    cond do
      not is_nil(post.reblog_of_id) -> "reblog"
      not is_nil(post.in_reply_to_id) -> "reply"
      true -> "mention"
    end
  end

  defp action_text("like"), do: "liked your post"
  defp action_text("favourite"), do: "liked your post"
  defp action_text("follow"), do: "followed you"
  defp action_text("reblog"), do: "boosted your post"
  defp action_text("reply"), do: "replied to your thread"
  defp action_text(_), do: "interacted with your profile"

  @doc """
  Fetches an active chronological history stream of notifications for a user profile.
  Preloads the interaction actor to guarantee single-pass database speeds .
  """
  def list_user_notifications(user_id, params \\ %{}) do
    limit = Map.get(params, "limit", 20)
    cursor = Map.get(params, "cursor")

    base_query =
      from(n in Notification,
        where: n.user_id == ^user_id,
        # CRITICAL: Grabs user profiles in one pass to avoid N+1 traps
        preload: [:actor]
      )

    query =
      if cursor,
        do: from(n in base_query, where: n.id < ^cursor),
        else: base_query

    query
    # Keyset sorting matching primary key index layouts
    |> order_by([n], desc: n.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # ─── ASYNC ENQUEUE CONTROLLERS (Offloads work away from the Web Thread) ───

  @doc """
  Pushes a standard notification payload task onto the background Oban queue.
  Returns immediately, keeping the client HTTP request running at peak speed.
  """
  def enqueue_notify(target_user_id, actor_id, type, attrs \\ %{}, data_payload \\ %{}) do
    %{
      "target_user_id" => to_string(target_user_id),
      "actor_id" => to_string(actor_id),
      "type" => type,
      "attrs" => stringify_keys(attrs),
      "data_payload" => stringify_keys(data_payload)
    }
    |> Kollective.Workers.NotificationWorker.new()
    |> Oban.insert()
  end

  @doc """
  Pushes a thread/conversation reply alert challenge onto the background Oban queue.
  Prevents heavy post threads from stuttering during multi-user interaction spikes.
  """
  def enqueue_reply(recipient_id, actor_id, post_id) do
    %{
      "recipient_id" => to_string(recipient_id),
      "actor_id" => to_string(actor_id),
      "post_id" => to_string(post_id)
    }
    |> Kollective.Workers.NotificationWorker.new()
    |> Oban.insert()
  end

  # Private normalizer helper to clean atom maps before database storage operations
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(val), do: val
end

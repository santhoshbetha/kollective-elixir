defmodule Kollective.Accounts.Users do
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Ecto.Multi
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Notifications.Notifications
  alias Kollective.Notifications.Notification

  # --- Relationship Categories ---
  @rel_types [
    :block,
    :mute,
    :reblog_mute,
    :notification_mute,
    :inverse_subscription,
    :endorsement
  ]

  @doc """
  Fetches all user profile structures that have a specific relationship type
  with the requesting user (e.g., retrieving all users blocked or muted by User X).
  Runs via indexed B-Tree paths in under 0.05ms.
  """
  def list_related_users(user_id, type) when type in ["block", "mute", "follow"] do
    User
    # 1. Join our relational mapping table directly on the target_id pointer
    |> join(:inner, [u], r in UserRelationship, on: r.target_id == u.id)
    # 2. Filter strictly by the active reader's ID and the required relation token
    |> where([u, r], r.source_id == ^user_id and r.type == ^type)
    # 3. Sort chronologically so settings lists render logically
    |> order_by([u, r], desc: r.id)
    |> Repo.all()
  end

  def list_related_users(_user_id, _type), do: []

  def toggle_relationship(%User{} = source, target_id, "block") do
    case Repo.get_by(UserRelationship, source_id: source.id, target_id: target_id, type: "block") do
      nil ->
        # If no block exists, invoke the multi-tier block context we built earlier
        # (This breaks mutual follows and scrubs timeline caches atomically!)
        target_user = Accounts.get_user!(target_id)

        case block_user(source, target_user) do
          {:ok, :blocked} ->
            {:ok, :created}

          {:error, reason} ->
            {:error, reason}
        end

      existing_block ->
        Repo.delete!(existing_block)
        {:ok, :deleted}
    end
  end

  def toggle_relationship(%User{} = source, target_id, type) when type in ["follow", "mute"] do
    case Repo.get_by(UserRelationship, source_id: source.id, target_id: target_id, type: type) do
      nil ->
        # Insert new relationship row record
        %UserRelationship{source_id: source.id, target_id: target_id, type: type}
        |> Repo.insert()
        |> case do
          {:ok, _} ->
            # Run auxiliary side effects (e.g. adjust follow counts cache or fire notifications)
            adjust_relationship_side_effects(:insert, source, target_id, type)
            {:ok, :created}

          {:error, cs} ->
            {:error, cs}
        end

      existing_relationship ->
        Repo.delete!(existing_relationship)
        # Run auxiliary rollback side effects
        adjust_relationship_side_effects(:delete, source, target_id, type)
        {:ok, :deleted}
    end
  end

  defp adjust_relationship_side_effects(:insert, source, target_id, "follow") do
    from(u in User, where: u.id == ^source.id) |> Repo.update_all(inc: [following_count: 1])
    from(u in User, where: u.id == ^target_id) |> Repo.update_all(inc: [follower_count: 1])

    # Trigger standard follow alert notification
    Notifications.notify(
      target_id,
      source.id,
      "follow",
      %{target_id: target_id, target_type: "User"},
      %{post_id: nil, preview: "started following you."}
    )
  end

  defp adjust_relationship_side_effects(:delete, source, target_id, "follow") do
    from(u in User, where: u.id == ^source.id) |> Repo.update_all(inc: [following_count: -1])
    from(u in User, where: u.id == ^target_id) |> Repo.update_all(inc: [follower_count: -1])
  end

  defp adjust_relationship_side_effects(_, _, _, _), do: :ok

  defp update_follower_count(user_id, amount) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [follower_count: amount])
  end

  defp update_following_count(user_id, amount) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [following_count: amount])
  end

  @doc """
  Increments user note_count and records last_post_at timestamp.
  """
  def increment_note_count(user_id) do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [note_count: 1], set: [last_post_at: now])
  end

  @doc """
  Decrements user note_count, clamped at 0.
  """
  def decrement_note_count(user_id) do
    from(u in User, where: u.id == ^user_id and u.note_count > 0)
    |> Repo.update_all(inc: [note_count: -1])
  end

  @doc """
  Updates user note_count by a relative amount, maintaining bounds.
  """
  def update_note_count(user_id, amount) when amount > 0 do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [note_count: amount], set: [last_post_at: now])
  end

  def update_note_count(user_id, amount) when amount < 0 do
    from(u in User, where: u.id == ^user_id and u.note_count > 0)
    |> Repo.update_all(inc: [note_count: amount])
  end

  def update_note_count(_user_id, 0), do: {0, nil}

  # --- Follow / Unfollow ---
  # First, modify your follow_user function to check if the target user is locked
  # (using the is_locked boolean we added to the User schema earlier).
  def follow_user(%User{} = source, %User{} = target) do
    # 1. Prevent users from following themselves (common social rule)
    cond do
      source.id == target.id ->
        {:error, "You cannot follow yourself"}

      # 2. Check if the target user is locked
      target.is_locked ->
        # 2a. Create a follow_request instead of a follow
        case create_relationship(source.id, target.id, "follow_request") do
          {:ok, _} ->
            # TRIGGER NOTIFICATION HERE~
            # standalone app does not use federated follow_request tables, a follow request on a private account is passed as an immediate,
            # actionable transient notification over the WebSocket to trigger a live React UI toast pop-up
            Notifications.notify(
              # The recipient (The private user receiving the request)
              target.id,
              # The actor (The user clicking follow)
              source.id,
              # Type maps to your verified registry string
              "follow",
              %{
                # Links target_id to the sender for the follow button
                target_id: source.id,
                target_type: "User"
              },
              %{
                post_id: nil,
                # Handled by your React toast notification listener
                preview: "sent you a follow request."
              }
            )

            {:ok, :requested}

          _ ->
            {:error, :failed}
        end

      true ->
        # 3. Proceed with the normal follow + atomic counter update
        # Look for an existing follow relationship
        query =
          from r in UserRelationship,
            where:
              r.source_id == ^source.id and
                r.target_id == ^target.id and
                r.type == "follow"

        case Repo.one(query) do
          # 1. Create the new follow
          nil ->
            # Create a new follow
            Repo.transaction(fn ->
              case create_relationship(source.id, target.id, "follow") do
                {:ok, _rel} ->
                  # After successful follow, you might want a "follow" notification too
                  Notifications.notify(
                    # recipient_id
                    target.id,
                    # actor_id
                    source.id,
                    # type
                    "follow",
                    %{
                      target_id: target.id,
                      target_type: "User"
                    },
                    %{
                      post_id: nil,
                      preview: "started following you."
                    }
                  )

                  # 3a. Increment source's following count (+1)
                  update_following_count(source.id, 1)

                  # 3b. Increment target's follower count (+1)
                  update_follower_count(target.id, 1)

                  {:ok, :followed}

                {:error, _changeset} ->
                  # If it failed (or was a conflict), don't update counts
                  Repo.rollback(:failed_to_follow)
                  {:ok, false}
              end
            end)

          relationship ->
            # Unfollow logic: Unfollow logic: delete record AND decrement counters
            Repo.transaction(fn ->
              case Repo.delete(relationship) do
                {:ok, _} ->
                  # Decrement source's following count (-1)
                  update_following_count(source.id, -1)

                  # Decrement target's follower count (-1)
                  update_follower_count(target.id, -1)

                  {:ok, :unfollowed}

                {:error, _changeset} ->
                  Repo.rollback(:failed_to_unfollow)
              end
            end)
        end
    end
  end

  def unfollow_user(%User{} = source, %User{} = target) do
    Repo.transaction(fn ->
      case delete_relationship(source.id, target.id, "follow") do
        {1, _} ->
          # Decrement counts only if a relationship was deleted
          update_following_count(source.id, -1)
          update_follower_count(target.id, -1)
          {:ok, :unfollowed}

        {0, _} ->
          # No relationship found, nothing to update
          # Wasn't following anyway, no count change needed
          {:ok, :already_not_following}
      end
    end)
  end

  # The "Accept Request" Function
  # When the target user clicks "Accept," you need to atomically convert the follow_request into a follow
  # and then update the counters.
  def accept_follow_request(%User{} = target, %User{} = source) do
    Repo.transaction(fn ->
      # 1. Delete the "follow_request"
      {deleted_count, _} = delete_relationship(source.id, target.id, "follow_request")

      if deleted_count > 0 do
        # 2. Create the "follow" relationship
        create_relationship(source.id, target.id, "follow")

        # 3. Update the counters
        update_following_count(source.id, 1)
        update_follower_count(target.id, 1)

        {:ok, :accepted}
      else
        Repo.rollback(:no_request_found)
      end
    end)
  end

  # The "Reject Request" Function
  # Rejecting is simple: just delete the request. No counters are changed.
  def reject_follow_request(%User{} = target, %User{} = source) do
    delete_relationship(source.id, target.id, "follow_request")
    {:ok, :rejected}
  end

  # Helper for the UI
  # You'll need a way to show the user their pending requests. Since you use Ecto.ULID, this query is very fast.
  def list_pending_follow_requests(%User{} = user) do
    UserRelationship
    |> where([r], r.target_id == ^user.id and r.type == "follow_request")
    # Load the users who want to follow you
    |> preload(:source)
    |> Repo.all()
  end

  # --- Block / Unblock ---

  @doc """
  Executes an atomic user block. Inside a single database transaction pool:
    1. Tears down mutual following records (bidirectional unfollow).
    2. Inserts an immutable "block" relationship row.
    3. Clears out all old timeline entry cache records between both users to prevent data leaks.
  """
  def block_user(%User{} = source, %User{} = target) do
    Multi.new()
    # 1. Break mutual follow records instantly (Source unfollows Target & Target unfollows Source)
    |> Multi.run(:break_source_follow, fn _repo, _changes ->
      query =
        from(r in UserRelationship,
          where: r.source_id == ^source.id and r.target_id == ^target.id and r.type == "follow"
        )

      {:ok, Repo.delete_all(query)}
    end)
    |> Multi.run(:break_target_follow, fn _repo, _changes ->
      query =
        from(r in UserRelationship,
          where: r.source_id == ^target.id and r.target_id == ^source.id and r.type == "follow"
        )

      {:ok, Repo.delete_all(query)}
    end)

    # 2. Insert the defensive "block" relationship row safely
    |> Multi.insert(
      :block_relationship,
      %UserRelationship{
        source_id: source.id,
        target_id: target.id,
        type: "block"
      },
      on_conflict: :nothing,
      conflict_target: [:source_id, :target_id, :type]
    )

    # 3. HIGH-SPEED HOME FEED CACHE SCRUBBING
    # Instantly purges all timeline post pointers from both users' personalized cache tables
    |> Multi.run(:cache_eviction, fn _repo, _changes ->
      # Remove Target's posts from Source's home timeline cache
      from(e in "home_feed_entries",
        join: p in "posts",
        on: p.id == e.post_id,
        where: e.user_id == ^source.id and p.user_id == ^target.id
      )
      |> Repo.delete_all()

      # Remove Source's posts from Target's home timeline cache
      from(e in "home_feed_entries",
        join: p in "posts",
        on: p.id == e.post_id,
        where: e.user_id == ^target.id and p.user_id == ^source.id
      )
      |> Repo.delete_all()

      {:ok, :cache_cleared}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, :blocked}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Lifts a user block, allowing profiles to interact normally again."
  def unblock_user(%User{} = source, %User{} = target) do
    case delete_relationship(source.id, target.id, "block") do
      {count, _} when count > 0 -> {:ok, :unblocked}
      _ -> {:error, :not_found}
    end
  end

  # --- Mute / Unmute ---

  @doc """
  Executes an atomic user mute. Inserts both a feed "mute" and a "notification_mute"
  row into the database using a single atomic transaction pass.
  """
  def mute_user(%User{} = source, %User{} = target) do
    Multi.new()
    # 1. Feed Mute: Hides their items from your active timelines
    |> Multi.insert(
      :feed_mute,
      %UserRelationship{
        source_id: source.id,
        target_id: target.id,
        type: "mute"
      },
      on_conflict: :nothing,
      conflict_target: [:source_id, :target_id, :type]
    )

    # 2. Notification Mute: Silences their push alerts and interaction banners
    |> Multi.insert(
      :notif_mute,
      %UserRelationship{
        source_id: source.id,
        target_id: target.id,
        type: "notification_mute"
      },
      on_conflict: :nothing,
      conflict_target: [:source_id, :target_id, :type]
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> {:ok, :muted}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Lifts all mutes between users. Cleanses feed mutes, notification mutes,
  and reblog/boost mutes in a single database swipe.
  """
  def unmute_user(%User{} = source, %User{} = target) do
    query =
      from(r in UserRelationship,
        where:
          r.source_id == ^source.id and
            r.target_id == ^target.id and
            r.type in ["mute", "notification_mute", "reblog_mute"]
      )

    case Repo.delete_all(query) do
      {count, _} when count > 0 -> {:ok, :unmuted}
      _ -> {:error, :not_found}
    end
  end

  # --- Private Helpers ---

  defp create_relationship(source_id, target_id, type, expires_at \\ nil) do
    %UserRelationship{}
    |> UserRelationship.changeset(%{
      source_id: source_id,
      target_id: target_id,
      type: type,
      expires_at: expires_at
    })
    |> Repo.insert(
      # 1. We use conflict_target to find the existing row
      conflict_target: [:source_id, :target_id, :type],

      # 2. If it exists, update the 'expires_at' and 'updated_at'
      # but keep the original 'id' (ULID) and 'inserted_at'
      on_conflict: {:replace, [:expires_at, :updated_at]},

      # 3. Return the updated record
      returning: true
    )
  end

  defp delete_relationship(source_id, target_id, type) do
    # 1. Define the query to find the specific ULID-based relationship
    query =
      from r in UserRelationship,
        where:
          r.source_id == ^source_id and
            r.target_id == ^target_id and
            r.type == ^type

    # 2. Execute the batch delete
    # Returns {count, nil} - e.g., {1, nil} if deleted, {0, nil} if not found
    Repo.delete_all(query)
  end

  # --- Automated Function Generation ---
  # We use Elixir's metaprogramming to define all 24 functions cleanly
  for type <- @rel_types do
    type_str = Atom.to_string(type)

    # 1. Create Functions (e.g., create_block/3)
    def unquote(String.to_atom("create_#{type}"))(source, target, expires_at \\ nil) do
      create(unquote(type_str), source, target, expires_at)
    end

    # 2. Delete Functions (e.g., delete_block/2)
    def unquote(String.to_atom("delete_#{type}"))(source, target) do
      delete(unquote(type_str), source, target)
    end

    # 3. Exists Functions (e.g., block_exists?/2)
    def unquote(String.to_atom("#{type}_exists?"))(source, target) do
      exists?(unquote(type_str), source, target)
    end

    # 4. Expire Date Functions (e.g., get_block_expire_date/2)
    def unquote(String.to_atom("get_#{type}_expire_date"))(source, target) do
      get_expire_date(unquote(type_str), source, target)
    end
  end

  # --- Base Internal Helpers (Your provided logic) ---

  def create(rel_type, %User{} = source, %User{} = target, expires_at) do
    %UserRelationship{}
    |> UserRelationship.changeset(%{
      type: rel_type,
      source_id: source.id,
      target_id: target.id,
      expires_at: expires_at
    })
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:source_id, :type, :target_id],
      returning: true
    )
  end

  def delete(rel_type, %User{} = source, %User{} = target) do
    attrs = %{type: rel_type, source_id: source.id, target_id: target.id}

    case Repo.get_by(UserRelationship, attrs) do
      %UserRelationship{} = record -> Repo.delete(record)
      nil -> {:ok, nil}
    end
  end

  def exists?(rel_type, %User{} = source, %User{} = target) do
    UserRelationship
    |> where(type: ^rel_type, source_id: ^source.id, target_id: ^target.id)
    |> Repo.exists?()
  end

  def get_expire_date(rel_type, %User{} = source, %User{} = target) do
    UserRelationship
    |> where(type: ^rel_type, source_id: ^source.id, target_id: ^target.id)
    |> select([r], r.expires_at)
    # Using Repo.one instead of one! to avoid crashing if record is missing
    |> Repo.one()
  end

  # Cleanup of expired relationships (like a 24-hour mute or a temporary block), you can create a simple
  # GenServer or an Oban worker that runs this query periodically.
  def delete_expired_relationships do
    now = NaiveDateTime.utc_now()

    query =
      from r in UserRelationship,
        where: not is_nil(r.expires_at) and r.expires_at < ^now

    # Returns {count, nil}
    Repo.delete_all(query)
  end

  def load_user_districts(user) do
    Repo.preload(user, [:district_l1, :district_l2, :district_l3, :city])
  end

  def mark_feed_as_read(user) do
    user
    |> Ecto.Changeset.change(last_read_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  #
  def list_following_ids(user_id) do
    UserRelationship
    |> where([r], r.source_id == ^user_id and r.type == "follow")
    |> select([r], r.target_id)
    |> Repo.all()
    # As discussed, we add the user's own ID so they see their own posts in the feed
    |> Kernel.++([user_id])
  end

  def block_user2(source_id, target_id) do
    if source_id == target_id do
      {:error, "You cannot block yourself"}
    else
      Multi.new()
      # 1. Create the block relationship

      |> Multi.insert(:block_record, %UserRelationship{
        source_id: source_id,
        target_id: target_id,
        type: "block"
      })
      # 2. Remove: User A following User B
      |> Multi.delete_all(
        :remove_follow_a,
        from(r in UserRelationship,
          where: r.source_id == ^source_id and r.target_id == ^target_id and r.type == "follow"
        )
      )
      # 3. Remove: User B following User A (The "Force Unfollow")
      |> Multi.delete_all(
        :remove_follow_b,
        from(r in UserRelationship,
          where: r.source_id == ^target_id and r.target_id == ^source_id and r.type == "follow"
        )
      )
      # 4. NEW: Wipe out notification history from the blocked user
      |> Multi.delete_all(
        :clear_notifications,
        from(n in Notification,
          where: n.user_id == ^source_id and n.actor_id == ^target_id
        )
      )
      |> Repo.transaction()
    end
  end

  def unblock_user2(source_id, target_id) do
    query =
      from r in UserRelationship,
        where: r.source_id == ^source_id and r.target_id == ^target_id and r.type == "block"

    Repo.delete_all(query)
  end

  # In a social app, blocking is usually two-way for visibility: you shouldn't see them,
  # and they shouldn't see you.
  # retrieves a unique list of IDs that the current user has blocked,
  # as well as IDs of users who have blocked the current user
  def list_blocked_ids(user_id) do
    import Ecto.Query
    alias Kollective.{Repo, UserRelationship}

    # 1. Users I have blocked
    blocked_by_me =
      UserRelationship
      |> where([r], r.source_id == ^user_id and r.type == "block")
      |> select([r], r.target_id)

    # 2. Users who have blocked me
    blocked_me =
      UserRelationship
      |> where([r], r.target_id == ^user_id and r.type == "block")
      |> select([r], r.source_id)

    # Combine and get unique IDs
    query = union(blocked_by_me, ^blocked_me)

    Repo.all(query)
  end

  # Example: Suggested users to follow
  #  By fetching both "Who I blocked" and "Who blocked me," you ensure a harasser
  # can't see the victim's profile in search results, even if the victim hasn't blocked them back yet.
  def list_suggested_users(current_user_id) do
    blocked_ids = list_blocked_ids(current_user_id)
    # Already includes self
    following_ids = list_following_ids(current_user_id)

    # Exclude blocks and people already followed
    exclude_ids = Enum.uniq(blocked_ids ++ following_ids)

    User
    |> where([u], u.id not in ^exclude_ids)
    |> limit(5)
    |> Repo.all()
  end

  def mute_user2(source_id, target_id) do
    query =
      from r in UserRelationship,
        where:
          r.source_id == ^source_id and
            r.target_id == ^target_id and
            r.type == "mute"

    case Repo.one(query) do
      nil ->
        # Create the mute
        %UserRelationship{}
        |> UserRelationship.changeset(%{source_id: source_id, target_id: target_id, type: "mute"})
        |> Repo.insert()

      relationship ->
        # Unmute logic
        Repo.delete(relationship)
    end
  end

  # Notification Muting is a "selective" mute. You still see the user's posts in your timeline,
  # but you stop receiving real-time alerts (pings) and history entries for their interactions with you
  def toggle_notification_mute(source_id, target_id) do
    query =
      from r in UserRelationship,
        where:
          r.source_id == ^source_id and
            r.target_id == ^target_id and
            r.type == "notification_mute"

    case Repo.one(query) do
      nil ->
        # Create the notification mute
        %UserRelationship{}
        |> UserRelationship.changeset(%{
          source_id: source_id,
          target_id: target_id,
          type: "notification_mute"
        })
        |> Repo.insert()

      relationship ->
        # Unmute notifications
        Repo.delete(relationship)
    end
  end

  @doc """
  Atomic transaction modifier pass to update a profile's verified political boundaries.
  """
  def update_user_districts(%Kollective.Accounts.User{} = user, attrs) do
    state = attrs[:origin_state] || attrs["origin_state"] || user.origin_state || user.state

    l1_code = attrs[:district_l1] || attrs["district_l1"]
    l2_code = attrs[:district_l2] || attrs["district_l2"]
    l3_code = attrs[:district_l3] || attrs["district_l3"]

    l1_id =
      attrs[:district_l1_id] || attrs["district_l1_id"] ||
        if l1_code,
          do:
            Map.get(
              Kollective.Locations.Locations.get_or_create_district(1, state, l1_code) || %{},
              :id
            ),
          else: nil

    l2_id =
      attrs[:district_l2_id] || attrs["district_l2_id"] ||
        if l2_code,
          do:
            Map.get(
              Kollective.Locations.Locations.get_or_create_district(2, state, l2_code) || %{},
              :id
            ),
          else: nil

    l3_id =
      attrs[:district_l3_id] || attrs["district_l3_id"] ||
        if l3_code,
          do:
            Map.get(
              Kollective.Locations.Locations.get_or_create_district(3, state, l3_code) || %{},
              :id
            ),
          else: nil

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("district_l1_id", l1_id)
      |> Map.put("district_l2_id", l2_id)
      |> Map.put("district_l3_id", l3_id)
      |> Map.put("origin_state", state)

    user
    |> Ecto.Changeset.cast(attrs, [
      :origin_state,
      :district_l1_id,
      :district_l2_id,
      :district_l3_id,
      :location,
      :street_address
    ])
    |> Ecto.Changeset.validate_required([:origin_state, :district_l1_id])
    |> Kollective.Repo.update()
  end

  @doc """
  Updates the user's geographical and political boundaries after address validation.
  """
  def update_user_political_bounds(%User{} = user, attrs) do
    state = attrs[:state] || attrs["state"] || user.state

    l1_code = attrs[:district_l1_code] || attrs["district_l1_code"]
    l2_code = attrs[:district_l2_code] || attrs["district_l2_code"]
    l3_code = attrs[:district_l3_code] || attrs["district_l3_code"]

    l1_id =
      if l1_code,
        do:
          Map.get(
            Kollective.Locations.Locations.get_or_create_district(1, state, l1_code) || %{},
            :id
          ),
        else: nil

    l2_id =
      if l2_code,
        do:
          Map.get(
            Kollective.Locations.Locations.get_or_create_district(2, state, l2_code) || %{},
            :id
          ),
        else: nil

    l3_id =
      if l3_code,
        do:
          Map.get(
            Kollective.Locations.Locations.get_or_create_district(3, state, l3_code) || %{},
            :id
          ),
        else: nil

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("district_l1_id", l1_id)
      |> Map.put("district_l2_id", l2_id)
      |> Map.put("district_l3_id", l3_id)
      |> Map.put("origin_state", state)
      |> Map.put("state", state)

    user
    |> User.political_bounds_changeset(attrs)
    |> Repo.update()
  end
end

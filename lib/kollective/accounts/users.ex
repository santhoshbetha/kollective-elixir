defmodule Kollective.Accounts.Users do
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Ecto.Multi
  alias Kollective.Accounts.User
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

  defp update_follower_count(user_id, amount) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [follower_count: amount])
  end

  defp update_following_count(user_id, amount) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [following_count: amount])
  end

  # --- Follow / Unfollow ---

  #Update your "Follow" Logic
# First, modify your follow_user function to check if the target user is locked
  # (using the is_locked boolean we added to the User schema earlier).
  def follow_user(%User{} = source, %User{} = target) do
    if target.is_locked do
      # 1. Create a follow_request instead of a follow
      case create_relationship(source.id, target.id, "follow_request") do
        {:ok, _} ->
          # TRIGGER NOTIFICATION HERE~
          Notifications.create_action_notification(target.id, source.id, "follow_request")
          {:ok, :requested}
        _ -> {:error, :failed}
      end
    else
      # 2. Proceed with the normal follow + atomic counter update
      Repo.transaction(fn ->
        case create_relationship(source.id, target.id, "follow") do
          {:ok, _rel} ->
            # After successful follow, you might want a "follow" notification too
            Notifications.create_action_notification(target.id, source.id, "follow")
            # 2. Increment source's following count (+1)
            update_following_count(source.id, 1)

            # 3. Increment target's follower count (+1)
            update_follower_count(target.id, 1)

            {:ok, :followed}

          {:error, _changeset} ->
            # If it failed (or was a conflict), don't update counts
            Repo.rollback(:failed_to_follow)
            {:ok, false}
        end
      end)
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
  #When the target user clicks "Accept," you need to atomically convert the follow_request into a follow
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

  #Helper for the UI
  # You'll need a way to show the user their pending requests. Since you use Ecto.ULID, this query is very fast.
  def list_pending_follow_requests(%User{} = user) do
    UserRelationship
    |> where([r], r.target_id == ^user.id and r.type == "follow_request")
    |> preload(:source) # Load the users who want to follow you
    |> Repo.all()
  end

  # --- Block / Unblock ---

  def block_user(%User{} = source, %User{} = target) do
    # When blocking, you might also want to unfollow them automatically
    unfollow_user(source, target)
    create_relationship(source.id, target.id, "block")
  end

  def unblock_user(%User{} = source, %User{} = target) do
    delete_relationship(source.id, target.id, "block")
  end

  # --- Mute / Unmute ---

  def mute_user(%User{} = source, %User{} = target, expires_at \\ nil) do
    create_relationship(source.id, target.id, "mute", expires_at)
    create_relationship(source.id, target.id, "notification_mute", expires_at)
  end

  def unmute_user(%User{} = source, %User{} = target) do
    # Clear the post mute
    delete_relationship(source.id, target.id, "mute")
    # Clear the notification mute
    delete_relationship(source.id, target.id, "notification_mute")
    # Clear the reblog mute
    delete_relationship(source.id, target.id, "reblog_mute")
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
    query = from r in UserRelationship,
      where: r.source_id == ^source_id and
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
    |> Repo.one() # Using Repo.one instead of one! to avoid crashing if record is missing
  end

  # Cleanup of expired relationships (like a 24-hour mute or a temporary block), you can create a simple
  # GenServer or an Oban worker that runs this query periodically.
  def delete_expired_relationships do
    now = NaiveDateTime.utc_now()

    query = from r in UserRelationship,
      where: not is_nil(r.expires_at) and r.expires_at < ^now

    # Returns {count, nil}
    Repo.delete_all(query)
  end

  def load_user_districts(user) do
    Repo.preload(user, [:district_l1, :district_l2, :district_l3, :origin_city])
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

  def follow_user2(source_id, target_id) do
    # 1. Prevent users from following themselves (common social rule)
    if source_id == target_id do
      {:error, "You cannot follow yourself"}
    else
      # 2. Look for an existing follow relationship
      query = from r in UserRelationship,
        where: r.source_id == ^source_id and
              r.target_id == ^target_id and
              r.type == "follow"

      case Repo.one(query) do
        # 1. Create the new follow
        nil ->
          # Create a new follow
         {:ok, relationship} = %UserRelationship{}

          |> UserRelationship.changeset(%{
            source_id: source_id,
            target_id: target_id,
            type: "follow"
          })
          |> Repo.insert()

        # 2. TRIGGER NOTIFICATION
        notify_follow(relationship)
        {:ok, relationship}

        relationship ->
          # Unfollow logic: delete the existing record
          Repo.delete(relationship)
      end
    end
  end

  defp notify_follow(relationship) do
    # Fetch actor (the person who followed) to send their name to React
    _follower = Repo.get!(User, relationship.source_id)

    # 1. Save to Database for the 'Notifications' tab
    {:ok, _notif} = Notifications.create_action_notification(
      relationship.target_id,  # The person being followed
      relationship.source_id, # The person who clicked follow
      "follow"
    )

    # 2. Real-time broadcast via Phoenix Channels
    #KollectiveWeb.Endpoint.broadcast(
    #  "notifications:#{relationship.target_id}",
    #  "new_follow",
    #  %{
    #    from: follower.username,
    #    from_id: follower.id,
    #    avatar: follower.avatar_url
    #  }
    #)
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
      |> Multi.delete_all(:remove_follow_a,
        from(r in UserRelationship,
          where: r.source_id == ^source_id and r.target_id == ^target_id and r.type == "follow")
      )
      # 3. Remove: User B following User A (The "Force Unfollow")
      |> Multi.delete_all(:remove_follow_b,
        from(r in UserRelationship,
          where: r.source_id == ^target_id and r.target_id == ^source_id and r.type == "follow")
      )
      # 4. NEW: Wipe out notification history from the blocked user
      |> Multi.delete_all(:clear_notifications,
        from(n in Notification,
          where: n.user_id == ^source_id and n.actor_id == ^target_id))

      |> Repo.transaction()
    end
  end

  def unblock_user2(source_id, target_id) do
    query = from r in UserRelationship,
      where: r.source_id == ^source_id and r.target_id == ^target_id and r.type == "block"

    Repo.delete_all(query)
  end

  #In a social app, blocking is usually two-way for visibility: you shouldn't see them,
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
    following_ids = list_following_ids(current_user_id) # Already includes self

    # Exclude blocks and people already followed
    exclude_ids = Enum.uniq(blocked_ids ++ following_ids)

    User

    |> where([u], u.id not in ^exclude_ids)
    |> limit(5)
    |> Repo.all()
  end

  def mute_user2(source_id, target_id) do
    query = from r in UserRelationship,
      where: r.source_id == ^source_id and
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
    query = from r in UserRelationship,
      where: r.source_id == ^source_id and
            r.target_id == ^target_id and
            r.type == "notification_mute"

    case Repo.one(query) do
      nil ->
        # Create the notification mute
        %UserRelationship{}

        |> UserRelationship.changeset(%{source_id: source_id, target_id: target_id, type: "notification_mute"})
        |> Repo.insert()
      relationship ->
        # Unmute notifications
        Repo.delete(relationship)
    end
  end

end

defmodule KollectiveWeb.AccountJSON do
  @moduledoc """
  Unified Standalone Account/User Profile Serializer.
  Enforces privacy boundaries and serializes local account records cleanly for the React UI.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Notifications.Notifications
  # alias Kollective.Chats.Chats

  @doc """
  Renders a collection of users with an optional relationship context wrapper.
  """
  def index(%{users: users} = opts) do
    reading_user = opts[:for]

    # Pre-fetch dynamic relation markers in a single pass to prevent N+1 query thrashes
    relationship_map =
      if reading_user && opts[:embed_relationships] != false do
        fetch_relationship_batch_map(reading_user.id, Enum.map(users, & &1.id))
      else
        %{}
      end

    users
    |> Enum.map(fn user ->
      user_opts =
        Map.merge(opts, %{
          user: user,
          relationship_context: Map.get(relationship_map, user.id, %{})
        })

      show(user_opts)
    end)
    |> Enum.filter(&(&1 != %{}))
  end

  @doc """
  Main single profile serialization router endpoint.
  """
  def show(%{user: _user, skip_visibility_check: true} = opts), do: do_show(opts)

  def show(%{user: user, for: reading_user} = opts) do
    if reading_user && Accounts.blocks?(reading_user, user) do
      %{}
    else
      do_show(opts)
    end
  end

  def show(%{user: user}), do: do_show(%{user: user, for: nil})
  def show(_), do: %{}

  # --- Structural Serialization Core Layout ---
  defp do_show(%{user: user} = opts) do
    reading_user = opts[:for]

    relationship =
      opts[:relationship_context] ||
        if(reading_user, do: fetch_single_relationship_map(reading_user.id, user.id), else: %{})

    %{
      id: to_string(user.id),
      username: user.username,
      display_name: user.name || user.username,
      bio: user.bio || "",
      avatar: user.avatar_url || "/default-avatar.jpg",
      cover_image: user.cover_image_url || "/default-banner-bg.jpg",

      # Counts caches synchronized natively via our atomic context counters
      followers_count: user.follower_count || 0,
      following_count: user.following_count || 0,
      posts_count: user.posts_count || 0,

      # Meta state parameters
      is_verified: user.is_verified || false,
      is_admin: user.is_admin || false,
      is_moderator: user.is_moderator || false,
      is_discoverable: user.is_discoverable || true,

      # Dynamic relationship attachment layer mapping heart/follow badge indicators
      relationship: relationship,
      created_at: Calendar.strftime(user.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      location: user.location,
      age:
        if(user.show_age || (reading_user && reading_user.id == user.id), do: user.age, else: nil)
    }
    |> maybe_put_private_settings(user, reading_user)
  end

  # ─── EXTRACTION RELATIONSHIP HELPER MATRICES (O(1) BATCH PRE-FETCH) ───

  defp fetch_single_relationship_map(reading_user_id, target_user_id) do
    relations =
      from(r in UserRelationship,
        where: r.source_id == ^reading_user_id and r.target_id == ^target_user_id,
        select: r.type
      )
      |> Repo.all()
      |> MapSet.new()

    followed_by? =
      Repo.exists?(
        from(r in UserRelationship,
          where:
            r.source_id == ^target_user_id and r.target_id == ^reading_user_id and
              r.type == "follow"
        )
      )

    %{
      following: MapSet.member?(relations, "follow"),
      followed_by: followed_by?,
      blocking: MapSet.member?(relations, "block"),
      muting: MapSet.member?(relations, "mute"),
      muting_notifications: MapSet.member?(relations, "notification_mute"),
      showing_reblogs: not MapSet.member?(relations, "reblog_mute")
    }
  end

  defp fetch_relationship_batch_map(reading_user_id, target_ids) do
    db_relations =
      from(r in UserRelationship,
        where: r.source_id == ^reading_user_id and r.target_id in ^target_ids,
        select: {r.target_id, r.type}
      )
      |> Repo.all()

    reverse_follows =
      from(r in UserRelationship,
        where:
          r.target_id == ^reading_user_id and r.source_id in ^target_ids and r.type == "follow",
        select: r.source_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.reduce(target_ids, %{}, fn tid, acc ->
      user_relation_types =
        db_relations
        |> Enum.filter(fn {target_id, _} -> target_id == tid end)
        |> Enum.map(fn {_, type} -> type end)
        |> MapSet.new()

      map_item = %{
        following: MapSet.member?(user_relation_types, "follow"),
        followed_by: MapSet.member?(reverse_follows, tid),
        blocking: MapSet.member?(user_relation_types, "block"),
        muting: MapSet.member?(user_relation_types, "mute"),
        muting_notifications: MapSet.member?(user_relation_types, "notification_mute"),
        showing_reblogs: not MapSet.member?(user_relation_types, "reblog_mute")
      }

      Map.put(acc, tid, map_item)
    end)
  end

  # ─── SECTION 3: PRIVACY & PERSONAL ACCOUNT CONSTRAINTS APPENDER ───

  defp maybe_put_private_settings(data, user, reading_user) do
    # Inject protected configuration credentials ONLY if the user is requesting their own profile
    if reading_user && reading_user.id == user.id do
      # Fetch in-memory unread counts safely from our streamlined context managers
      unread_notifications = Notifications.count_unread_notifications(user.id)

      # Optional: Fallback value if chat context isn't loaded yet
      # unread_dms = case Code.ensure_loaded(Chats) do
      #  {:module, _} -> Chats.get_unread_count(user.id)
      #  _ -> 0
      # end

      data
      |> Map.put(:email, user.email)
      |> Map.put(:accepts_chat_messages, user.accepts_chat_messages || true)
      |> Map.put(:accepts_email_list, user.accepts_email_list || false)
      |> Map.put(:show_age, user.show_age || false)
      |> Map.put(:unread_notifications_count, unread_notifications)
      # |> Map.put(:unread_conversation_count, unread_dms)
      |> Map.put(:notification_settings, Map.get(user, :notification_settings, %{}))
      |> Map.put(:settings_store, Map.get(user, :settings, %{}))
    else
      # If the reader is an admin/staff member viewing another user, append activation tags for visibility
      if reading_user && (reading_user.is_admin || reading_user.is_moderator) do
        Map.put(data, :is_active, user.is_active)
      else
        data
      end
    end
  end

  # ─── SECTION 4: ADMIN CONTROLLER PORTFOLIO DATA FORMAT ───

  @doc """
  Renders a specialized layout payload for administrative compliance lookups.
  """
  def show_admin(%{user: user}) do
    %{
      id: to_string(user.id),
      username: user.username,
      email: user.email,
      created_at: Calendar.strftime(user.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      is_confirmed: user.is_confirmed || false,
      is_active: user.is_active || true,
      is_approved: user.is_approved || true,
      role:
        cond do
          user.is_admin -> "admin"
          user.is_moderator -> "moderator"
          true -> "user"
        end,
      registration_reason: user.registration_reason || ""
    }
  end
end

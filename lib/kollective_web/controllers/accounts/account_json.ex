defmodule KollectiveWeb.AccountJSON do
  @moduledoc """
  Unified Standalone Account/User Profile Serializer.
  Enforces privacy boundaries and serializes local account records cleanly for the React UI.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Civic.Vouch
  alias Kollective.Notifications.Notifications
  # alias Kollective.Chats.Chats

  @doc """
  Renders a collection of users with an optional relationship context wrapper.
  """
  def index(%{users: users} = opts) do
    reading_user = opts[:for]

    # Pre-fetch dynamic relation markers and vouch counts in a single pass to prevent N+1 query thrashes
    relationship_map =
      if reading_user && opts[:embed_relationships] != false do
        fetch_relationship_batch_map(reading_user.id, Enum.map(users, & &1.id))
      else
        %{}
      end

    vouch_count_map = Vouch.batch_count_for_users(Enum.map(users, & &1.id))

    users
    |> Enum.map(fn user ->
      user_opts =
        Map.merge(opts, %{
          user: user,
          relationship_context: Map.get(relationship_map, user.id, %{}),
          vouch_count_map: vouch_count_map
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

  @doc """
  Serializes comprehensive profile data for the authenticated user, returned after
  successful login or credential verification, modeled after Mastodon's
  CredentialAccount format and enriched with Kollective platform metadata.
  """
  def profile_data(%User{} = user), do: login_profile(user)
  def profile_data(user) when is_map(user), do: login_profile(user)

  def login_profile(%User{} = user) do
    unread_notifications = Notifications.count_unread_notifications(user.id)
    fields = extract_verification_fields(user)
    is_sensitive = default_sensitive?(user)

    avatar = resolve_avatar(user)
    cover = resolve_cover(user)

    vouch_count = resolve_vouch_count(user)
    is_peer_vouched = (user.account_tier || 0) >= 1 or vouch_count >= 1
    is_vouched = is_peer_vouched or (user.is_verified || false)

    %{
      # ─── 1. CORE PROFILE DETAILS ───
      id: to_string(user.id),
      username: user.username,
      acct: user.username,
      display_name: user.display_name || user.username,
      bio: user.bio || "",
      note: user.bio || "",
      raw_bio: user.raw_bio || user.bio || "",
      avatar: avatar,
      avatar_url: avatar,
      header: cover,
      header_url: cover,
      cover_image: cover,
      created_at: Calendar.strftime(user.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      email: user.email,
      location: user.location,
      state: user.state,
      country: user.country,
      state_updated_at: user.state_updated_at,
      type: to_string(user.type || :citizen),
      representative_name: user.representative_name,

      # ─── 2. SOCIAL METADATA ───
      followers_count: user.follower_count || 0,
      following_count: user.following_count || 0,
      posts_count: user.note_count || 0,
      last_post_at:
        if(user.last_post_at, do: NaiveDateTime.to_iso8601(user.last_post_at), else: nil),
      unread_notifications_count: unread_notifications,

      # ─── 3. VERIFICATION FIELDS ───
      fields: fields,
      custom_fields: fields,
      is_verified: user.is_verified || false,
      verified_title: user.verified_title,
      official_website: user.official_website,
      badge_type: user.badge_type || "ClassicBlue",

      # ─── 4. PRIVACY SETTINGS ───
      privacy_settings: %{
        default_visibility: user.default_scope || "public",
        default_sensitive: is_sensitive,
        is_locked: user.is_locked || false,
        is_discoverable: user.is_discoverable != false,
        is_invisible: user.is_invisible || false,
        hide_followers_count: user.hide_followers_count || false,
        hide_follows_count: user.hide_follows_count || false,
        hide_followers: user.hide_followers || false,
        hide_follows: user.hide_follows || false,
        hide_favorites: user.hide_favorites != false,
        accepts_chat_messages: user.accepts_chat_messages != false
      },
      # Mastodon-compatible source sub-object
      source: %{
        privacy: user.default_scope || "public",
        sensitive: is_sensitive,
        language: user.locale || user.language || "en",
        note: user.raw_bio || user.bio || "",
        fields: fields,
        follow_requests_count: 0
      },

      # ─── 5. INTERFACE SETTINGS ───
      interface_settings: %{
        locale: user.locale || "en",
        language: user.language || user.locale || "en",
        auto_play_gifs: user.auto_play_gifs || false,
        theme: get_in(user.settings || %{}, ["theme"]) || "system",
        no_rich_text: user.no_rich_text || false,
        experience_mode: user.experience_mode || "social_only"
      },
      preferences: %{
        locale: user.locale || "en",
        auto_play_gifs: user.auto_play_gifs || false,
        theme: get_in(user.settings || %{}, ["theme"]) || "system"
      },

      # ─── 6. FEATURE FLAGS ───
      feature_flags: %{
        is_admin: user.is_admin || user.role == :admin || false,
        is_moderator: user.is_moderator || user.role == :moderator || false,
        can_moderate: user.is_admin || user.is_moderator || user.role in [:admin, :moderator],
        is_candidate: user.is_candidate || false,
        is_verified_candidate: user.is_verified_candidate || false,
        can_manage_organizations: user.type == :organization || user.is_admin || false,
        is_exempt: user.is_exempt || false,
        is_shadow_banned: user.is_shadow_banned || false,
        account_tier: user.account_tier || 0,
        is_peer_vouched: is_peer_vouched,
        is_vouched: is_vouched,
        vouch_count: vouch_count,
        role: to_string(user.role || :user)
      },

      # ─── 7. PLATFORM CONTEXT ───
      political_location: %{
        country: user.country,
        state: user.state,
        state_updated_at: user.state_updated_at,
        county: user.county,
        city_name: user.city_name,
        district_l1_id: user.district_l1_id,
        district_l2_id: user.district_l2_id,
        district_l3_id: user.district_l3_id
      },
      notification_settings: Map.get(user, :notification_settings, %{}) || %{},
      settings_store: Map.get(user, :settings, %{}) || %{}
    }
  end

  def login_profile(_), do: %{}

  # --- Structural Serialization Core Layout ---
  defp do_show(%{user: user} = opts) do
    reading_user = opts[:for]

    relationship =
      opts[:relationship_context] ||
        if(reading_user, do: fetch_single_relationship_map(reading_user.id, user.id), else: %{})

    avatar = resolve_avatar(user)
    cover = resolve_cover(user)

    vouch_count = resolve_vouch_count(user, opts)
    is_peer_vouched = (user.account_tier || 0) >= 1 or vouch_count >= 1
    is_vouched = is_peer_vouched or (user.is_verified || false)

    %{
      id: to_string(user.id),
      username: user.username,
      display_name: user.display_name || user.username,
      bio: user.bio || "",
      avatar: avatar,
      avatar_url: avatar,
      cover_image: cover,
      cover_image_url: cover,
      banner: cover,
      header: cover,
      header_url: cover,

      # Counts caches synchronized natively via our atomic context counters
      followers_count: user.follower_count || 0,
      following_count: user.following_count || 0,
      posts_count: user.note_count || 0,

      # Meta state parameters
      is_verified: user.is_verified || false,
      account_tier: user.account_tier || 0,
      is_peer_vouched: is_peer_vouched,
      is_vouched: is_vouched,
      vouch_count: vouch_count,
      is_admin: user.is_admin || false,
      is_moderator: user.is_moderator || false,
      is_discoverable: user.is_discoverable || true,
      type: to_string(user.type || :citizen),
      representative_name: user.representative_name,

      # Dynamic relationship attachment layer mapping heart/follow badge indicators
      relationship: relationship,
      following: Map.get(relationship, :following, false),
      followed_by: Map.get(relationship, :followed_by, false),
      created_at: Calendar.strftime(user.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
      location: user.location,
      age:
        if(user.show_age || (reading_user && reading_user.id == user.id), do: user.age, else: nil)
    }
    |> maybe_put_private_settings(user, reading_user)
  end

  defp resolve_vouch_count(user, opts \\ %{}) do
    vouch_map =
      cond do
        is_map(opts) && Map.has_key?(opts, :vouch_count_map) -> opts.vouch_count_map
        is_list(opts) && Keyword.has_key?(opts, :vouch_count_map) -> opts[:vouch_count_map]
        true -> %{}
      end

    user_id = Map.get(user, :id)

    cond do
      user_id && Map.has_key?(vouch_map, user_id) ->
        Map.get(vouch_map, user_id, 0)

      user_id && Map.has_key?(vouch_map, to_string(user_id)) ->
        Map.get(vouch_map, to_string(user_id), 0)

      Map.has_key?(user, :vouch_count) and not is_nil(user.vouch_count) ->
        user.vouch_count

      Ecto.assoc_loaded?(Map.get(user, :received_vouches)) ->
        length(user.received_vouches)

      user_id ->
        Vouch.count_for_user(user_id)

      true ->
        0
    end
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
      unread_notifications = Notifications.count_unread_notifications(user.id)
      fields = extract_verification_fields(user)
      is_sensitive = default_sensitive?(user)

      data
      |> Map.put(:email, user.email)
      |> Map.put(:state, user.state)
      |> Map.put(:street_address, user.street_address)
      |> Map.put(:district_l1, district_name(user.district_l1))
      |> Map.put(:district_l2, district_name(user.district_l2))
      |> Map.put(:district_l3, district_name(user.district_l3))
      |> Map.put(:note, user.bio || "")
      |> Map.put(:raw_bio, user.raw_bio || user.bio || "")
      |> Map.put(:accepts_chat_messages, user.accepts_chat_messages != false)
      |> Map.put(:accepts_email_list, user.accepts_email_list || false)
      |> Map.put(:show_age, user.show_age || false)
      |> Map.put(:unread_notifications_count, unread_notifications)
      |> Map.put(:notification_settings, Map.get(user, :notification_settings, %{}) || %{})
      |> Map.put(:settings_store, Map.get(user, :settings, %{}) || %{})
      |> Map.put(:fields, fields)
      |> Map.put(:custom_fields, fields)
      |> Map.put(:privacy_settings, %{
        default_visibility: user.default_scope || "public",
        default_sensitive: is_sensitive,
        is_locked: user.is_locked || false,
        is_discoverable: user.is_discoverable != false,
        is_invisible: user.is_invisible || false,
        hide_followers_count: user.hide_followers_count || false,
        hide_follows_count: user.hide_follows_count || false,
        hide_followers: user.hide_followers || false,
        hide_follows: user.hide_follows || false,
        hide_favorites: user.hide_favorites != false,
        accepts_chat_messages: user.accepts_chat_messages != false
      })
      |> Map.put(:source, %{
        privacy: user.default_scope || "public",
        sensitive: is_sensitive,
        language: user.locale || user.language || "en",
        note: user.raw_bio || user.bio || "",
        fields: fields,
        follow_requests_count: 0
      })
      |> Map.put(:interface_settings, %{
        locale: user.locale || "en",
        language: user.language || user.locale || "en",
        auto_play_gifs: user.auto_play_gifs || false,
        theme: get_in(user.settings || %{}, ["theme"]) || "system",
        no_rich_text: user.no_rich_text || false,
        experience_mode: user.experience_mode || "social_only"
      })
      |> Map.put(:preferences, %{
        locale: user.locale || "en",
        auto_play_gifs: user.auto_play_gifs || false,
        theme: get_in(user.settings || %{}, ["theme"]) || "system"
      })
      |> Map.put(:feature_flags, %{
        is_admin: user.is_admin || user.role == :admin || false,
        is_moderator: user.is_moderator || user.role == :moderator || false,
        can_moderate: user.is_admin || user.is_moderator || user.role in [:admin, :moderator],
        is_candidate: user.is_candidate || false,
        is_verified_candidate: user.is_verified_candidate || false,
        can_manage_organizations: user.type == :organization || user.is_admin || false,
        is_exempt: user.is_exempt || false,
        is_shadow_banned: user.is_shadow_banned || false,
        account_tier: user.account_tier || 0,
        role: to_string(user.role || :user)
      })
    else
      # If the reader is an admin/staff member viewing another user, append activation tags for visibility
      if reading_user && (reading_user.is_admin || reading_user.is_moderator) do
        Map.put(data, :is_active, user.is_active)
      else
        data
      end
    end
  end

  defp extract_verification_fields(user) do
    custom =
      get_in(user.settings || %{}, ["fields"]) ||
        get_in(user.metadata || %{}, ["fields"]) ||
        get_in(user.settings || %{}, ["custom_fields"]) ||
        get_in(user.metadata || %{}, ["custom_fields"]) ||
        []

    normalized =
      custom
      |> Enum.map(fn
        %{"name" => name, "value" => val} = item ->
          %{
            name: to_string(name),
            value: to_string(val),
            verified_at: item["verified_at"] || item[:verified_at]
          }

        %{name: name, value: val} = item ->
          %{
            name: to_string(name),
            value: to_string(val),
            verified_at: item[:verified_at] || item["verified_at"]
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    has_website? =
      Enum.any?(normalized, fn f ->
        String.downcase(f.name) in ["website", "official website", "official_website"] or
          (user.official_website != nil and f.value == user.official_website)
      end)

    extra =
      if user.official_website && not has_website? do
        [
          %{
            name: "Website",
            value: user.official_website,
            verified_at:
              if(user.is_verified,
                do: Calendar.strftime(user.updated_at || user.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),
                else: nil
              )
          }
        ]
      else
        []
      end

    normalized ++ extra
  end

  defp default_sensitive?(user) do
    settings = user.settings || %{}

    settings["default_sensitive"] ||
      settings["mark_media_sensitive"] ||
      settings["sensitive"] ||
      false
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
      suspended_at:
        if(user.suspended_at, do: NaiveDateTime.to_iso8601(user.suspended_at), else: nil),
      suspension_reason: user.suspension_reason
    }
  end

  defp district_name(nil), do: nil
  defp district_name(%Ecto.Association.NotLoaded{}), do: nil
  defp district_name(dist), do: dist.name || dist.type_label

  defp resolve_avatar(%{avatar_url: avatar_url} = user) when not is_nil(avatar_url) do
    Kollective.Media.UserAvatar.url({avatar_url, user}, :original) || "/default-avatar.jpg"
  end

  defp resolve_avatar(_), do: "/default-avatar.jpg"

  defp resolve_cover(%{cover_image_url: cover_url} = user) when not is_nil(cover_url) do
    Kollective.Media.UserCover.url({cover_url, user}, :original) || "/default-banner-bg.jpg"
  end

  defp resolve_cover(_), do: "/default-banner-bg.jpg"
end

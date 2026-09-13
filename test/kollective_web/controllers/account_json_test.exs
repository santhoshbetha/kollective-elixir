defmodule KollectiveWeb.AccountJSONTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.AccountsFixtures
  alias KollectiveWeb.AccountJSON

  setup do
    %{user: user_fixture()}
  end

  describe "profile_data/1" do
    test "serializes basic user correctly with all 6 required sections", %{user: user} do
      data = AccountJSON.profile_data(user)

      # 1. Core Profile Details
      assert data.id == to_string(user.id)
      assert data.username == user.username
      assert data.acct == user.username
      assert data.display_name == (user.display_name || user.username)
      assert data.bio == (user.bio || "")
      assert data.note == (user.bio || "")
      assert data.raw_bio == (user.raw_bio || user.bio || "")
      assert data.avatar == (user.avatar_url || "/default-avatar.jpg")
      assert data.avatar_url == (user.avatar_url || "/default-avatar.jpg")
      assert data.header == (user.cover_image_url || "/default-banner-bg.jpg")
      assert data.header_url == (user.cover_image_url || "/default-banner-bg.jpg")
      assert data.cover_image == (user.cover_image_url || "/default-banner-bg.jpg")
      assert data.created_at == Calendar.strftime(user.inserted_at, "%Y-%m-%dT%H:%M:%SZ")
      assert data.email == user.email
      assert data.type == to_string(user.type || :citizen)

      # 2. Social Metadata
      assert data.followers_count == (user.follower_count || 0)
      assert data.following_count == (user.following_count || 0)
      assert data.posts_count == (user.note_count || 0)
      assert is_integer(data.unread_notifications_count)

      # 3. Verification Fields
      assert is_list(data.fields)
      assert is_list(data.custom_fields)
      assert data.is_verified == (user.is_verified || false)
      assert data.badge_type == (user.badge_type || "ClassicBlue")

      # 4. Privacy Settings
      assert is_map(data.privacy_settings)

      assert data.privacy_settings.default_visibility in [
               "public",
               "unlisted",
               "private",
               "direct"
             ]

      assert is_boolean(data.privacy_settings.default_sensitive)
      assert is_boolean(data.privacy_settings.is_locked)
      assert is_boolean(data.privacy_settings.is_discoverable)

      assert is_map(data.source)
      assert data.source.privacy in ["public", "unlisted", "private", "direct"]
      assert is_boolean(data.source.sensitive)
      assert is_list(data.source.fields)

      # 5. Interface Settings
      assert is_map(data.interface_settings)
      assert data.interface_settings.locale == (user.locale || "en")
      assert is_boolean(data.interface_settings.auto_play_gifs)
      assert is_map(data.preferences)

      # 6. Feature Flags
      assert is_map(data.feature_flags)
      assert is_boolean(data.feature_flags.is_admin)
      assert is_boolean(data.feature_flags.is_moderator)
      assert is_boolean(data.feature_flags.can_moderate)
      assert is_boolean(data.feature_flags.can_manage_organizations)
      assert is_binary(data.feature_flags.role)
    end

    test "serializes candidate, moderator, and custom verification links properly", %{user: user} do
      updated_user =
        user
        |> Ecto.Changeset.change(%{
          is_moderator: true,
          role: :moderator,
          is_candidate: true,
          is_verified_candidate: true,
          verified_title: "City Council Member",
          official_website: "https://candidate.org",
          is_verified: true,
          default_scope: "private",
          settings: %{
            "default_sensitive" => true,
            "theme" => "oled",
            "fields" => [
              %{
                "name" => "Civic Blog",
                "value" => "https://candidate.org/blog",
                "verified_at" => "2026-03-01T12:00:00Z"
              }
            ]
          }
        })
        |> Kollective.Repo.update!()

      data = AccountJSON.profile_data(updated_user)

      # Verification Fields
      assert data.is_verified == true
      assert data.verified_title == "City Council Member"
      assert data.official_website == "https://candidate.org"

      field_names = Enum.map(data.fields, & &1.name)
      assert "Civic Blog" in field_names
      assert "Website" in field_names

      # Privacy Settings
      assert data.privacy_settings.default_visibility == "private"
      assert data.privacy_settings.default_sensitive == true
      assert data.source.privacy == "private"
      assert data.source.sensitive == true

      # Interface Settings
      assert data.interface_settings.theme == "oled"

      # Feature Flags
      assert data.feature_flags.is_moderator == true
      assert data.feature_flags.can_moderate == true
      assert data.feature_flags.is_candidate == true
      assert data.feature_flags.is_verified_candidate == true
      assert data.feature_flags.role == "moderator"
    end
  end
end

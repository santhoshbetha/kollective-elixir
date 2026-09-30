defmodule KollectiveWeb.UserJSON do
  @moduledoc """
  Unified Account Identity Profile Serializer.
  Formats structural user database metadata matrices safely for the React UI.
  """

  def show(%{user: user}) do
    %{data: data(user)}
  end

  def data(user) do
    # 🚀 DYNAMIC MEDIA PATH CONSTRUCTORS: Resolve absolute CDN target links safely
    avatar =
      if user.avatar_url,
        do: Kollective.Media.UserAvatar.url({user.avatar_url, user}, :original),
        else: "/default-avatar.jpg"

    cover =
      if user.cover_image_url,
        do: Kollective.Media.UserCover.url({user.cover_image_url, user}, :original),
        else: "/default-banner-bg.jpg"

    %{
      id: user.id,
      username: user.username,
      email: user.email,

      # 📸 HIGH-PERFORMANCE VISUAL ASSET FIELDS
      avatar_url: avatar,
      avatar: avatar,
      cover_image_url: cover,
      cover: cover,

      # POLITICAL IDS (For API Calls)
      districts: %{
        l1: user.district_l1_id,
        l2: user.district_l2_id,
        l3: user.district_l3_id
      },

      # READABLE NAMES (For UI Labels/Breadcrumbs)
      district_names: %{
        l1:
          (Ecto.assoc_loaded?(user.district_l1) && user.district_l1 && user.district_l1.name) ||
            "National",
        l2:
          (Ecto.assoc_loaded?(user.district_l2) && user.district_l2 && user.district_l2.name) ||
            "State",
        l3:
          (Ecto.assoc_loaded?(user.district_l3) && user.district_l3 && user.district_l3.name) ||
            "Local"
      },

      # GEOGRAPHY
      city_name: user.city_name || (Ecto.assoc_loaded?(user.city) && user.city && user.city.name),
      state: user.state,
      state_updated_at: user.state_updated_at,
      country: user.country,
      country_code: user.country,
      street_address: user.street_address,
      county: user.county,
      school_district_code: user.school_district_code,
      city_council_district_code: user.city_council_district_code,
      is_candidate: user.is_candidate,
      is_verified_candidate: user.is_verified_candidate,
      settings: %{
        auto_play_gifs: user.auto_play_gifs
      }
    }
  end
end

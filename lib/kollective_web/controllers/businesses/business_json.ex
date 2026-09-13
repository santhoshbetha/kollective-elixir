defmodule KollectiveWeb.BusinessJSON do
  @moduledoc """
  JSON serializer for businesses and business proposals.
  """

  def show(%{business: business}) do
    %{status: "success", data: data(business)}
  end

  def index(%{businesses: items}), do: index(items)

  def index(items) when is_list(items) do
    Enum.map(items, &list_item/1)
  end

  def leaderboard(%{top_ideas: top_ideas}), do: leaderboard(top_ideas)

  def leaderboard(top_ideas) when is_list(top_ideas) do
    Enum.map(top_ideas, &leaderboard_item/1)
  end

  def registration_data(business) do
    %{
      id: to_string(business.id),
      name: business.name,
      legal_structure: business.legal_structure,
      business_hours: Map.get(business.metadata || %{}, "business_hours", %{})
    }
  end

  def proposal_data(proposal) do
    %{
      id: to_string(proposal.id),
      title: proposal.name,
      category: proposal.category,
      funding_details: Map.get(proposal.metadata || %{}, "funding_data", %{})
    }
  end

  def list_item(item) do
    %{
      id: to_string(item.id),
      name: item.name,
      category: item.category,
      sub_category: item.sub_category,
      type: item.type,
      verification_status: item.verification_status,
      inserted_at: format_datetime(item.inserted_at),
      owner: serialize_owner(item)
    }
  end

  def leaderboard_item(idea) do
    %{
      id: to_string(idea.id),
      name: idea.name,
      slug: Map.get(idea, :slug),
      bio: Map.get(idea, :bio) || Map.get(idea, :description),
      category: idea.category,
      sub_category: idea.sub_category,
      type: idea.type,
      verification_status: idea.verification_status,
      upvotes_count: idea.upvotes_count,
      inserted_at: format_datetime(idea.inserted_at),
      owner: serialize_owner(idea)
    }
  end

  def data(item) do
    %{
      id: to_string(item.id),
      name: item.name,
      description: item.description,
      type: item.type,
      category: item.category,
      sub_category: item.sub_category,
      verification_status: item.verification_status,
      upvotes_count: item.upvotes_count,
      comments_count: item.comments_count,
      inserted_at: format_datetime(item.inserted_at),
      legal_structure: item.legal_structure,
      business_hours: Map.get(item.metadata || %{}, "business_hours", %{}),

      # Contact Details
      contact: contact_details(item),
      contact_details: contact_details(item),

      # Corporate / Metrics Details
      metrics: corporate_details(item),
      corporate_details: corporate_details(item),

      # Dynamic JSONB Data Layer Blocks
      funding_details: Map.get(item.metadata || %{}, "funding_data", %{}),
      additional_metadata: Map.delete(item.metadata || %{}, "funding_data"),
      metadata: item.metadata || %{},

      # Geographic Location Properties
      geography: %{
        district_l1: item.district_l1,
        district_l2: item.district_l2,
        district_l3: item.district_l3,
        coordinates: unpack_coordinates(item.location)
      },
      district_l1: item.district_l1,
      district_l2: item.district_l2,
      district_l3: item.district_l3,

      # Unified Owner Struct Serialization
      owner: serialize_owner(item)
    }
  end

  defp contact_details(item) do
    %{
      address: item.address,
      city: item.city,
      state: item.state,
      zip: item.zip,
      country: item.country,
      email: item.email,
      phone: item.phone,
      website: item.website
    }
  end

  defp corporate_details(item) do
    %{
      legal_structure: item.legal_structure,
      year_established: item.year_established,
      number_of_employees: item.number_of_employees,
      profile_image_url: item.profile_image_url
    }
  end

  defp serialize_owner(%{user: %Ecto.Association.NotLoaded{}}), do: nil
  defp serialize_owner(%{user: nil}), do: nil

  defp serialize_owner(%{user: user}) do
    %{
      id: to_string(user.id),
      username: user.username,
      avatar_url: user.avatar_url
    }
  end

  defp serialize_owner(_), do: nil

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_datetime(_), do: nil

  defp unpack_coordinates(%Geo.Point{coordinates: {lng, lat}}),
    do: %{longitude: lng, latitude: lat}

  defp unpack_coordinates(_), do: nil
end

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
    meta = business.metadata || %{}

    %{
      id: to_string(business.id),
      name: business.name,
      legal_structure: business.legal_structure,
      business_hours: Map.get(meta, "business_hours", "9:00 AM - 5:00 PM"),
      hours: Map.get(meta, "business_hours") || Map.get(meta, "hours", "9:00 AM - 5:00 PM"),
      profile_image_url: business.profile_image_url,
      image: business.profile_image_url,
      services: Map.get(meta, "services", []),
      tags: Map.get(meta, "tags", [])
    }
  end

  def proposal_data(proposal) do
    meta = proposal.metadata || %{}
    funding = Map.get(meta, "funding_data", %{})
    money_req = Map.get(funding, "money_required") || Map.get(funding, "fundingGoal") || 0
    min_inv = Map.get(funding, "minimum_amount") || Map.get(funding, "minInvest") || 0
    max_inv = Map.get(funding, "maximum_amount") || Map.get(funding, "maxInvest") || 0

    %{
      id: to_string(proposal.id),
      name: proposal.name,
      title: proposal.name,
      description: proposal.description,
      category: proposal.category,
      sub_category: proposal.sub_category,
      status: Map.get(funding, "status", "New"),
      fundingGoal: money_req,
      money_required: money_req,
      minInvest: min_inv,
      maxInvest: max_inv,
      percent: Map.get(funding, "percent", 0),
      daysLeft: Map.get(funding, "daysLeft", 45),
      participants: Map.get(funding, "participants", "0 Members"),
      funding_details: funding,
      funding_data: funding,
      owner: serialize_owner(proposal),
      owner_name: serialize_owner_name(proposal),
      ownerAvatar: serialize_owner_avatar(proposal)
    }
  end

  def list_item(item) do
    meta = item.metadata || %{}
    funding = Map.get(meta, "funding_data", %{})
    money_req = Map.get(funding, "money_required") || Map.get(funding, "fundingGoal") || 0
    min_inv = Map.get(funding, "minimum_amount") || Map.get(funding, "minInvest") || 0
    max_inv = Map.get(funding, "maximum_amount") || Map.get(funding, "maxInvest") || 0

    %{
      id: to_string(item.id),
      name: item.name,
      title: item.name,
      description: item.description,
      category: item.category,
      sub_category: item.sub_category,
      type: item.type,
      verification_status: item.verification_status,
      verified: item.verification_status == "verified",
      open: true,
      rating: Map.get(meta, "rating", 5.0),
      reviewsCount: Map.get(meta, "reviews_count", 0),
      image: item.profile_image_url,
      profile_image_url: item.profile_image_url,
      address: item.address,
      city: item.city,
      state: item.state,
      zip: item.zip,
      phone: item.phone,
      email: item.email,
      website: item.website,
      hours: Map.get(meta, "business_hours") || Map.get(meta, "hours", "9:00 AM - 5:00 PM"),
      established: item.year_established,
      year_established: item.year_established,
      employees:
        Map.get(meta, "employee_range") ||
          if(item.number_of_employees, do: to_string(item.number_of_employees), else: "1-5"),
      services: Map.get(meta, "services", []),
      tags: Map.get(meta, "tags", []),
      # Proposal specific fields:
      status: Map.get(funding, "status", "New"),
      fundingGoal: money_req,
      money_required: money_req,
      minInvest: min_inv,
      maxInvest: max_inv,
      percent: Map.get(funding, "percent", 0),
      daysLeft: Map.get(funding, "daysLeft", 45),
      participants: Map.get(funding, "participants", "0 Members"),
      funding_details: funding,
      inserted_at: format_datetime(item.inserted_at),
      owner: serialize_owner(item),
      owner_name: serialize_owner_name(item),
      ownerAvatar: serialize_owner_avatar(item)
    }
  end

  def leaderboard_item(idea) do
    _meta = idea.metadata || %{}

    %{
      id: to_string(idea.id),
      name: idea.name,
      title: idea.name,
      slug: Map.get(idea, :slug),
      bio: Map.get(idea, :bio) || Map.get(idea, :description),
      category: idea.category,
      sub_category: idea.sub_category,
      type: idea.type,
      verification_status: idea.verification_status,
      upvotes_count: idea.upvotes_count,
      inserted_at: format_datetime(idea.inserted_at),
      owner: serialize_owner(idea),
      owner_name: serialize_owner_name(idea),
      ownerAvatar: serialize_owner_avatar(idea)
    }
  end

  def data(item) do
    meta = item.metadata || %{}
    funding = Map.get(meta, "funding_data", %{})
    money_req = Map.get(funding, "money_required") || Map.get(funding, "fundingGoal") || 0
    min_inv = Map.get(funding, "minimum_amount") || Map.get(funding, "minInvest") || 0
    max_inv = Map.get(funding, "maximum_amount") || Map.get(funding, "maxInvest") || 0

    %{
      id: to_string(item.id),
      name: item.name,
      title: item.name,
      description: item.description,
      type: item.type,
      category: item.category,
      sub_category: item.sub_category,
      verification_status: item.verification_status,
      verified: item.verification_status == "verified",
      open: true,
      upvotes_count: item.upvotes_count,
      comments_count: item.comments_count,
      inserted_at: format_datetime(item.inserted_at),
      legal_structure: item.legal_structure,
      business_hours:
        Map.get(meta, "business_hours") || Map.get(meta, "hours", "9:00 AM - 5:00 PM"),
      hours: Map.get(meta, "business_hours") || Map.get(meta, "hours", "9:00 AM - 5:00 PM"),
      image: item.profile_image_url,
      profile_image_url: item.profile_image_url,
      rating: Map.get(meta, "rating", 5.0),
      reviewsCount: Map.get(meta, "reviews_count", 0),
      established: item.year_established,
      year_established: item.year_established,
      employees:
        Map.get(meta, "employee_range") ||
          if(item.number_of_employees, do: to_string(item.number_of_employees), else: "1-5"),
      services: Map.get(meta, "services", []),
      tags: Map.get(meta, "tags", []),

      # Contact Details
      contact: contact_details(item),
      contact_details: contact_details(item),

      # Corporate / Metrics Details
      metrics: corporate_details(item),
      corporate_details: corporate_details(item),

      # Dynamic JSONB Data Layer Blocks & Proposal Metrics
      status: Map.get(funding, "status", "New"),
      fundingGoal: money_req,
      money_required: money_req,
      minInvest: min_inv,
      maxInvest: max_inv,
      percent: Map.get(funding, "percent", 0),
      daysLeft: Map.get(funding, "daysLeft", 45),
      participants: Map.get(funding, "participants", "0 Members"),
      funding_details: funding,
      additional_metadata: Map.delete(meta, "funding_data"),
      metadata: meta,

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
      owner: serialize_owner(item),
      owner_name: serialize_owner_name(item),
      ownerAvatar: serialize_owner_avatar(item)
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

  defp serialize_owner_name(%{user: %Ecto.Association.NotLoaded{}}), do: nil
  defp serialize_owner_name(%{user: nil}), do: nil
  defp serialize_owner_name(%{user: %{username: u}}) when is_binary(u), do: u
  defp serialize_owner_name(%{metadata: %{"owner_handle" => h}}) when is_binary(h), do: h
  defp serialize_owner_name(%{metadata: %{owner_handle: h}}) when is_binary(h), do: h
  defp serialize_owner_name(_), do: nil

  defp serialize_owner_avatar(%{user: %Ecto.Association.NotLoaded{}}), do: nil
  defp serialize_owner_avatar(%{user: nil}), do: nil
  defp serialize_owner_avatar(%{user: %{avatar_url: a}}) when is_binary(a), do: a
  defp serialize_owner_avatar(%{metadata: %{"owner_avatar" => a}}) when is_binary(a), do: a
  defp serialize_owner_avatar(%{metadata: %{owner_avatar: a}}) when is_binary(a), do: a
  defp serialize_owner_avatar(_), do: nil

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_datetime(_), do: nil

  defp unpack_coordinates(%Geo.Point{coordinates: {lng, lat}}),
    do: %{longitude: lng, latitude: lat}

  defp unpack_coordinates(_), do: nil
end

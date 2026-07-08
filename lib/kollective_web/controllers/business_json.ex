# lib/kollective_web/controllers/business_json.ex
defmodule KollectiveWeb.BusinessJSON do
  def show(%{business: business}) do
    %{data: data(business)}
  end

  def data(business) do
    %{
      id: business.id,
      name: business.name,
      description: business.description,
      type: business.type,
      category: business.category,
      sub_category: business.sub_category,
      verification_status: business.verification_status,
      upvotes_count: business.upvotes_count,
      comments_count: business.comments_count,

      # Unified Address Blocks
      contact: %{
        address: business.address,
        city: business.city,
        state: business.state,
        zip: business.zip,
        country: business.country,
        email: business.email,
        phone: business.phone,
        website: business.website
      },

      # Corporate Metrics
      metrics: %{
        year_established: business.year_established,
        number_of_employees: business.number_of_employees,
        legal_structure: business.legal_structure,
        profile_image_url: business.profile_image_url
      },

      # Geofencing Extraction
      geography: %{
        district_l1: business.district_l1,
        district_l2: business.district_l2,
        district_l3: business.district_l3,
        coordinates: unpack_coordinates(business.location)
      },

      # Unpack flexible JSONB attributes block directly
      metadata: business.metadata || %{}
    }
  end

  defp unpack_coordinates(%Geo.Point{coordinates: {lng, lat}}),
    do: %{longitude: lng, latitude: lat}

  defp unpack_coordinates(_), do: nil
end

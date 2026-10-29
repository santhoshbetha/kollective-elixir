defmodule KollectiveWeb.ClassifiedJSON do
  @moduledoc """
  JSON serializer for classified advertisements.
  Formats ads to directly match the React frontend ClassifiedsDirectoryPage and PostAdModal expectations.
  """
  alias Kollective.Classifieds.Classified

  def index(%{classifieds: classifieds}) do
    %{
      status: "success",
      classifieds: Enum.map(classifieds, &data/1),
      data: Enum.map(classifieds, &data/1)
    }
  end

  def show(%{classified: %Classified{} = classified}) do
    %{
      status: "success",
      classified: data(classified),
      data: data(classified)
    }
  end

  def data(%Classified{} = classified) do
    user_handle =
      cond do
        classified.organization && classified.organization.display_name ->
          classified.organization.display_name

        classified.organization && classified.organization.username ->
          "@#{classified.organization.username}"

        classified.user && classified.user.username ->
          "@#{classified.user.username}"

        true ->
          "@anonymous"
      end

    %{
      id: to_string(classified.id),
      title: classified.title,
      category: classified.category,
      price: classified.price,
      # Frontend card accesses ad.desc
      desc: classified.description,
      description: classified.description,
      # Frontend card accesses ad.user
      user: user_handle,
      user_id: to_string(classified.user_id),
      organization_id: if(classified.organization_id, do: to_string(classified.organization_id), else: nil),
      location: classified.location || classified.neighborhood,
      neighborhood: classified.neighborhood,
      duration_days: classified.duration_days,
      expires: format_expires_in(classified.expires_at),
      expires_at:
        if(classified.expires_at, do: DateTime.to_iso8601(classified.expires_at), else: nil),
      status: classified.status,
      images: classified.images || [],
      contact_info: classified.contact_info,
      email: classified.email,
      phone_number: classified.phone_number,
      district_id: if(classified.district_id, do: to_string(classified.district_id), else: nil),
      coordinates: unpack_coordinates(classified.geom),
      inserted_at:
        if(classified.inserted_at, do: DateTime.to_iso8601(classified.inserted_at), else: nil)
    }
  end

  defp unpack_coordinates(%Geo.Point{coordinates: {lng, lat}}),
    do: %{longitude: lng, latitude: lat}

  defp unpack_coordinates(_), do: nil

  defp format_expires_in(nil), do: "Unknown"

  defp format_expires_in(%DateTime{} = expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now, :second)

    cond do
      diff_seconds <= 0 ->
        "Expired"

      diff_seconds < 3600 ->
        minutes = max(1, div(diff_seconds, 60))
        "#{minutes} min left"

      diff_seconds < 86400 ->
        hours = max(1, div(diff_seconds, 3600))
        "#{hours} hours left"

      true ->
        days = div(diff_seconds, 86400)
        "#{days} #{if days == 1, do: "day", else: "days"} left"
    end
  end
end

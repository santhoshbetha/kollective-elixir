# lib/kollective/locations/geo_utilities.ex
defmodule Kollective.Locations.GeoUtilities do
  @moduledoc """
  Unified Structural Geospatial Adapter for Entities.
  Parses raw form inputs or fallbacks onto background text address geocoding lookups.
  """
  import Ecto.Changeset
  import Ecto.Query
  alias Kollective.Repo
  require Logger

  @doc """
  Safely intercepts latitude and longitude values from form maps.
  Returns the changeset unchanged if coordinates are absent, leaving room for background lookups.
  """
  def cast_postgis_location(changeset, attrs) do
    lat = attrs["latitude"] || attrs[:latitude]
    lng = attrs["longitude"] || attrs[:longitude]

    if lat && lng do
      parsed_lat = if is_binary(lat), do: String.to_float(lat), else: lat
      parsed_lng = if is_binary(lng), do: String.to_float(lng), else: lng

      geo_point = %Geo.Point{coordinates: {parsed_lng, parsed_lat}, srid: 4326}
      put_change(changeset, :location, geo_point)
    else
      changeset
    end
  end

  @doc """
  Asynchronous Geocoding Processor. Resolves raw text strings into spatial points
  via free, non-authenticated OpenStreetMap engines without blocking active web pools.
  """
  def geocode_address_to_postgis(business_id, schema_module, address_text) do
    # 1. URL encode the raw input query parameters safely
    encoded_query = URI.encode_query(%{"q" => address_text, "format" => "json", "limit" => 1})
    url = "https://openstreetmap.org#{encoded_query}"

    # 2. Fire the external network handshake using standard HTTP clients
    case Req.get(url, headers: [{"user-agent", "KollectiveApp/1.0"}], retry: false) do
      {:ok, %Req.Response{status: 200, body: [%{"lat" => lat_str, "lon" => lng_str} | _]}} ->
        lat = String.to_float(lat_str)
        lng = String.to_float(lng_str)
        geo_point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        # 3. Write coordinates straight to the entity row via atomic update passes
        from(x in schema_module, where: x.id == ^business_id)
        |> Repo.update_all(set: [location: geo_point])

        # 4. Notify active local channels that the spatial coordinates are fully populated
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:geo_resolution_complete, %{id: business_id, type: to_string(schema_module)}}
        )

      _error_or_empty_payload ->
        Logger.warning(
          "GEOCRE_RESOLUTION_FAILED: Could not find geographic coordinates for text: '#{address_text}'"
        )

        :ok
    end
  end
end

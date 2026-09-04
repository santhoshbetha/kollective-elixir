defmodule Kollective.Locations.Locations do
  use Kollective.Schemas.Schema
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Locations.City
  alias Kollective.Locations.PoliticalDistrict

  @base_url "http://api.geonames.org/getJSON"
  # Replace with your actual GeoNames username
  @username "your_geonames_username"

  def get_or_import_city(geoname_id) do
    case Repo.get_by(City, external_id: geoname_id) do
      nil ->
        # Fetch from GeoNames API and create local record
        fetch_and_create_city_from_geonames(geoname_id)

      city ->
        {:ok, city}
    end
  end

  defp fetch_and_create_city_from_geonames(geoname_id) do
    params = [geonameId: geoname_id, username: @username]

    case Req.get(@base_url, params: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        create_city_from_payload(body)

      {:ok, %Req.Response{status: status}} ->
        {:error, "GeoNames API returned status #{status}"}

      {:error, reason} ->
        {:error, "GeoNames request failed: #{inspect(reason)}"}
    end
  end

  defp create_city_from_payload(payload) do
    # Map GeoNames fields to our internal City schema
    with {:ok, lat} <- parse_float(payload["lat"]),
         {:ok, lng} <- parse_float(payload["lng"]) do
      attrs = %{
        name: payload["name"],
        # e.g., "TX" or "MH"
        state: payload["adminCode1"],
        # e.g., "US" or "IN"
        country: payload["countryCode"],
        external_id: to_string(payload["geonameId"]),
        latitude: lat,
        longitude: lng
      }

      %City{}
      |> City.changeset(attrs)
      |> Repo.insert()
    else
      :error -> {:error, "Invalid latitude or longitude in GeoNames response"}
    end
  end

  defp parse_float(value) when is_float(value), do: {:ok, value}
  defp parse_float(value) when is_integer(value), do: {:ok, value * 1.0}

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      _ -> :error
    end
  end

  defp parse_float(_), do: :error

  @doc """
  Fetches a district by ID and preloads its full hierarchy.
  Example: MLA -> MLC/State Senate -> MP/Congress
  """
  def get_district_with_hierarchy!(id) do
    PoliticalDistrict
    |> Repo.get!(id)
    # The syntax [parent: :parent] tells Ecto to load the parent,
    # and then load the parent of THAT parent.
    |> all_hierarchy()
  end

  # Helper to ensure we always get the full stack
  defp all_hierarchy(district) do
    Repo.preload(district, parent: :parent)
  end

  @doc """
  Finds or inserts a political district by level, state, and code/name.
  """
  def get_or_create_district(level, state, name_or_code)
      when not is_nil(name_or_code) and not is_nil(state) do
    name = format_district_name(level, state, name_or_code)
    type_label = district_type_label(level)

    case Repo.get_by(PoliticalDistrict, level: level, state: state, name: name) do
      nil ->
        {:ok, district} =
          %PoliticalDistrict{}
          |> Ecto.Changeset.change(%{
            level: level,
            state: state,
            name: name,
            type_label: type_label,
            country: "US"
          })
          |> Repo.insert()

        district

      district ->
        district
    end
  end

  def get_or_create_district(_level, _state, _name_or_code), do: nil

  defp format_district_name(1, state, code) do
    if String.contains?(code, "-") do
      code
    else
      "#{state}-#{code}"
    end
  end

  defp format_district_name(2, _state, code) do
    if String.starts_with?(code, "SD-") do
      code
    else
      "SD-#{code}"
    end
  end

  defp format_district_name(3, _state, code) do
    if String.starts_with?(code, "HD-") or String.starts_with?(code, "LD-") do
      code
    else
      "HD-#{code}"
    end
  end

  defp format_district_name(_, _state, name), do: name

  defp district_type_label(1), do: "Federal"
  defp district_type_label(2), do: "State Upper"
  defp district_type_label(3), do: "State Lower"
  defp district_type_label(_), do: "Local"

  @doc """
  Finds a district of a specific level (1, 2, or 3) that contains the given coordinates.
  PostGIS coordinates are ordered as (Longitude, Latitude) matching standard WGS84 (SRID 4326).
  """
  def find_district_by_coords(nil, _lat, _level, _country_code), do: nil
  def find_district_by_coords(_lon, nil, _level, _country_code), do: nil

  def find_district_by_coords(lon, lat, level, country_code) do
    with {:ok, lon_num} <- parse_float(lon),
         {:ok, lat_num} <- parse_float(lat) do
      point = %Geo.Point{coordinates: {lon_num, lat_num}, srid: 4326}

      PoliticalDistrict
      |> where([d], d.level == ^level and d.country == ^country_code)
      |> where([d], fragment("ST_Contains(?, ?)", d.geom, ^point))
      |> limit(1)
      |> Repo.one()
    else
      _ -> nil
    end
  end
end

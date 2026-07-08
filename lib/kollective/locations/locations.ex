defmodule Kollective.Locations.Locations do
  use Kollective.Schemas.Schema

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

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
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
end

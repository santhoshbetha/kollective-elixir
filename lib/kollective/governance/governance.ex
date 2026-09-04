defmodule Kollective.Governance.Governance do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Governance.{GeoNode, PincodeMapping, PoliticalOffice, LocationFactory}

  @doc """
  Polymorphic dispatcher. Safely handles incoming GPS lookups
  based on the targeted country code.
  """
  def resolve_global_ballot(country_code, %{"lat" => lat, "lng" => lng}) do
    cc = String.upcase(country_code)

    case cc do
      # 🇺🇸 US TRACK: Turn coordinates into an address text token,
      # then pipe it directly to Google Civic API Strategy
      "US" ->
        case reverse_geocode_to_address(lat, lng) do
          {:ok, address_string} ->
            resolve_global_ballot("US", %{"address" => address_string})

          {:error, reason} ->
            {:error, reason}
        end

      # 🇮🇳 INDIA TRACK: Uses your lightweight reverse-geocoder to extract PIN code
      # and query your local high-speed internal database
      "IN" ->
        resolve_india_by_coordinates(lat, lng)

      _other_country ->
        {:error, "Country track configuration not supported via coordinates."}
    end
  end

  # --- Track B: Standard Text Address Input Query Route ---
  def resolve_global_ballot(country_code, %{"address" => address}) do
    cc = String.upcase(country_code)

    with {:ok, strategy_module} <- LocationFactory.get_strategy(cc),
         {:ok, context} <- strategy_module.fetch_context(address) do
      offices =
        query_office_matrix(
          cc,
          context.state,
          context.county,
          context.city,
          context.sub_district,
          nil
        )

      {:ok, %{metadata: context, offices: offices}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp reverse_geocode_to_address(lat, lng) do
    url = "https://openstreetmap.org"
    query_params = [lat: lat, lon: lng, format: "json"]

    case Req.get(url, params: query_params, headers: [{"User-Agent", "Kollective/1.0"}]) do
      {:ok, %{status: 200, body: %{"display_name" => full_address}}} ->
        # e.g. Returns "100, Congress Avenue, Austin, Travis County, Texas..."
        {:ok, full_address}

      _error ->
        {:error, "Failed to resolve coordinates into a valid text address string."}
    end
  end

  defp resolve_india_by_coordinates(lat, lng) do
    url = "https://openstreetmap.org"
    query_params = [lat: lat, lon: lng, format: "json", addressdetails: 1]

    case Req.get(url, params: query_params, headers: [{"User-Agent", "Kollective/1.0"}]) do
      {:ok, %{status: 200, body: %{"address" => address}}} ->
        pincode = address["postcode"]
        detected_district = address["state_district"] || address["county"] || address["district"]

        # Pull offices via high-speed internal database PIN code engine
        resolve_by_pincode(pincode, detected_district)

      _error ->
        {:error, "Reverse-geocoding calculation failed for India."}
    end
  end

  # --- Track A: User Entered or Geocoded 6-Digit PIN code ---
  @doc """
  Attempts a high-speed hyper-local PIN code resolution match.
  If it fails, it gracefully falls back to broad district-level matching.
  """
  def resolve_by_pincode(pincode_str, fallback_district \\ nil) do
    clean_pin = String.trim(pincode_str)

    query =
      from m in PincodeMapping,
        join: node in assoc(m, :geo_node),
        where: m.pincode == ^clean_pin,
        select: node

    case Repo.all(query) |> Repo.preload(parent: :parent) do
      # 🚀 CRITICAL FAILOVER INTERCEPT TRIGGER:
      [] ->
        if fallback_district do
          execute_broad_district_fallback(fallback_district, clean_pin)
        else
          {:error, "No active election boundaries registered for PIN code #{clean_pin}."}
        end

      matched_nodes ->
        # Standard hyper-local execution track path
        offices =
          Enum.flat_map(matched_nodes, fn leaf ->
            state_name =
              cond do
                leaf.parent && leaf.parent.parent -> leaf.parent.parent.name
                leaf.parent -> leaf.parent.name
                true -> "Karnataka"
              end

            query_office_matrix("IN", state_name, leaf.parent_id, leaf.name, leaf.area_type)
          end)
          |> Enum.uniq_by(& &1.office_id)

        {:ok,
         %{
           strategy_used: "pincode_exact",
           metadata: %{pincode: clean_pin, fallback_used: false},
           local_bodies: matched_nodes,
           offices: offices
         }}
    end
  end

  @doc """
  🌟 THE DISTRICT FALLBACK ENGINE:
  Triggers when hyper-local data maps fail. It scales the query scope up to Level 2 (District),
  delivering macro-level ballot seats so the user never encounters an empty screen.
  """
  def execute_broad_district_fallback(district_name, clean_pin) do
    # 1. Spatially search for the parent macro district node (Level 2) in your data tree
    district_node =
      Repo.one(
        from n in GeoNode,
          where: n.country_code == "IN" and n.level == 2 and ilike(n.name, ^"%#{district_name}%"),
          limit: 1
      )
      |> Repo.preload(:parent)

    if is_nil(district_node) do
      {:error,
       "Could not resolve hyper-local data nor district fallback parameters for: #{district_name}"}
    else
      state_name = if district_node.parent, do: district_node.parent.name, else: "Karnataka"

      # 2. Query our universal offices rules matrix.
      offices =
        query_office_matrix("IN", state_name, district_node.id, district_node.name, nil)

      {:ok,
       %{
         strategy_used: "district_fallback",
         metadata: %{
           pincode: clean_pin,
           fallback_used: true,
           resolved_district: district_node.name,
           message: "Hyper-local ward mappings unavailable. Displaying macro district boundaries."
         },
         local_bodies: [district_node],
         offices: offices
       }}
    end
  end

  # =========================================================================
  # Shared Core Rules Matcher (6-arity)
  # =========================================================================
  def query_office_matrix(cc, state, county, city, sub_dist, resolved_area_type) do
    base_query =
      from(o in PoliticalOffice,
        where: o.country_code == ^cc,
        where: is_nil(o.state_restriction) or ilike(o.state_restriction, ^to_string(state)),
        where:
          is_nil(o.district_restriction) or
            ilike(o.district_restriction, ^to_string(county)) or
            ilike(o.district_restriction, ^to_string(city)) or
            ilike(o.district_restriction, ^to_string(sub_dist))
      )

    query =
      if is_nil(resolved_area_type) do
        from(o in base_query, where: is_nil(o.area_type))
      else
        from(o in base_query, where: is_nil(o.area_type) or o.area_type == ^resolved_area_type)
      end

    Repo.all(query)
  end

  # =========================================================================
  # Shared Core Rules Matcher (5-arity)
  # =========================================================================
  def query_office_matrix(cc, state, county_id, city, resolved_area_type) do
    base_query =
      from(o in PoliticalOffice,
        where: o.country_code == ^cc,
        where: is_nil(o.state_restriction) or ilike(o.state_restriction, ^to_string(state)),
        where:
          is_nil(o.district_restriction) or
            ilike(o.district_restriction, ^to_string(county_id)) or
            ilike(o.district_restriction, ^to_string(city))
      )

    query =
      if is_nil(resolved_area_type) do
        from(o in base_query, where: is_nil(o.area_type))
      else
        from(o in base_query, where: is_nil(o.area_type) or o.area_type == ^resolved_area_type)
      end

    Repo.all(query)
  end
end

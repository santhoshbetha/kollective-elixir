defmodule Kollective.Services.GeocodioClient do
  @api_url "https://api.geocod.io/v1.7/geocode"

  def fetch_civic_data(address) do
    api_key = System.get_env("GEOCODIO_API_KEY")

    query_params = %{
      "q" => address,
      "fields" => "cd,stateleg,school,disclosures",
      "api_key" => api_key
    }

    case Req.get(@api_url, params: query_params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_boundaries(body)}

      _error ->
        {:error, "Failed to resolve political boundaries"}
    end
  end

  def parse_boundariesX(%{"results" => [best_match | _]}) do
    fields = Map.get(best_match, "fields", %{})
    address_components = Map.get(best_match, "address_components", %{})

    # Safely extract specific election boundaries
    %{
      street_address: Map.get(best_match, "formatted_address"),
      county: Map.get(address_components, "county"),
      district_l1_code: get_nested(fields, ["congressional_districts", 0, "district_number"]),
      district_l2_code:
        get_nested(fields, ["state_legislative_districts", "senate", 0, "district_number"]),
      district_l3_code:
        get_nested(fields, ["state_legislative_districts", "house", 0, "district_number"]),
      school_district_code:
        get_nested(fields, ["school_districts", "unified", "name"]) ||
          get_nested(fields, ["school_districts", "elementary", "name"]),
      # Use local municipal codes or disclosures for city council boundaries
      city_council_district_code: get_nested(fields, ["disclosures", "local_jurisdiction"])
    }
  end

  def parse_boundariesX2(%{"results" => [best_match | _]}) do
    fields = Map.get(best_match, "fields", %{})
    address_components = Map.get(best_match, "address_components", %{})

    # 1. Determine if a real municipal/city government boundary exists
    # If the user is in an unincorporated area, Geocodio's type will not be "city/town"
    type = Map.get(address_components, "type")
    has_municipality = type in ["city", "town", "village", "borough"]
    city_name = Map.get(address_components, "city")

    # 2. Safely parse special districts
    school_data = Map.get(fields, "school_districts", %{})
    has_school = Map.has_key?(school_data, "unified") or Map.has_key?(school_data, "elementary")

    # Check for environmental/conservation districts
    has_conservation =
      Map.has_key?(fields, "disclosures") and
        has_utility_field?(fields, "soil_water")

    # 3. Assemble application footprint matrix
    applicable_ids = [
      "governor",
      "lt_governor",
      "atty_general",
      "sec_state",
      "state_treasurer",
      "state_auditor",
      "county_commissioner",
      "sheriff",
      "dist_attorney",
      "county_clerk",
      "tax_assessor",
      "county_treasurer"
    ]

    applicable_ids =
      if has_municipality, do: applicable_ids ++ ["mayor", "city_council"], else: applicable_ids

    applicable_ids = if has_school, do: applicable_ids ++ ["school_board"], else: applicable_ids

    applicable_ids =
      if has_conservation,
        do: applicable_ids ++ ["soil_water_conv", "public_utility"],
        else: applicable_ids

    # Append state-specific tokens dynamically right in the backend engine
    state = Map.get(address_components, "state")
    applicable_ids = append_state_specific_ids(applicable_ids, state)

    %{
      street_address: Map.get(best_match, "formatted_address"),
      county: Map.get(address_components, "county"),
      state: state,
      city_name: city_name,
      city_council_district_code:
        if(has_municipality, do: Map.get(fields, "disclosures") |> get_local_ward(), else: nil),
      school_district_code: get_school_name(school_data),
      district_l1_code: get_nested(fields, ["congressional_districts", 0, "district_number"]),
      district_l2_code:
        get_nested(fields, ["state_legislative_districts", "senate", 0, "district_number"]),
      district_l3_code:
        get_nested(fields, ["state_legislative_districts", "house", 0, "district_number"]),

      # This array acts as the master visibility switch for your React frontend configuration
      applicable_office_ids: applicable_ids
    }
  end

  defp append_state_specific_ids(ids, "TX"),
    do: ids ++ ["tx_county_judge", "tx_constable", "tx_jp", "tx_ag_comm", "tx_rr_comm"]

  defp append_state_specific_ids(ids, "LA"), do: ids ++ ["parish_president", "police_juror"]
  defp append_state_specific_ids(ids, "VA"), do: ids ++ ["va_comm_attorney", "va_comm_revenue"]
  defp append_state_specific_ids(ids, "NJ"), do: ids ++ ["nj_surrogate"]
  defp append_state_specific_ids(ids, "NY"), do: ids ++ ["ny_town_supervisor", "ny_town_board"]
  defp append_state_specific_ids(ids, "NE"), do: ids ++ ["ne_unicameral_senator"]
  defp append_state_specific_ids(ids, _), do: ids

  defp get_school_name(%{"unified" => %{"name" => name}}), do: name
  defp get_school_name(%{"elementary" => %{"name" => name}}), do: name
  defp get_school_name(_), do: nil

  defp get_local_ward(%{"local_jurisdiction" => %{"district" => dist}}), do: dist
  defp get_local_ward(_), do: nil

  defp has_utility_field?(fields, key), do: String.contains?(Kernel.inspect(fields), key)

  defp get_nested(map, keys) do
    paths =
      Enum.map(keys, fn
        key when is_integer(key) -> Access.at(key)
        key -> Access.key(key)
      end)

    get_in(map, paths)
  end

  def parse_boundaries(%{"results" => [best_match | _]}) do
    fields = Map.get(best_match, "fields", %{})
    address_components = Map.get(best_match, "address_components", %{})

    state = Map.get(address_components, "state") |> String.upcase()
    county = Map.get(address_components, "county")
    city = Map.get(address_components, "city")

    # 1. Distinguish between Town vs City (Crucial for NY/Northeast mapping)
    # Geocodio returns location types like "township" or "city" in the address components
    location_type = Map.get(address_components, "type") |> to_string()

    is_town =
      String.contains?(location_type, "town") or String.contains?(location_type, "township")

    is_city = location_type == "city" or (state == "VA" and String.contains?(city, "City"))

    # 2. Extract Precinct Subdivisions (Crucial for TX Constables/JPs)
    # Geocodio captures voting precinct numbers under political parameters
    precinct = get_in(fields, ["voting_districts", "precinct"])

    # 3. Assemble Universal Whitelist Core
    base_ids = [
      "governor",
      "lt_governor",
      "atty_general",
      "sec_state",
      "county_commissioner",
      "sheriff"
    ]

    # 4. Apply Intersecting Conditional Logic Layers
    base_ids = if is_city, do: base_ids ++ ["mayor", "city_council"], else: base_ids

    base_ids =
      if Map.has_key?(fields, "school_districts"),
        do: base_ids ++ ["school_board"],
        else: base_ids

    # 5. Append State-Specific Subdivision Rules Dynamically
    final_applicable_ids = compute_state_specific_bounds(base_ids, state, is_city, is_town)

    %{
      street_address: Map.get(best_match, "formatted_address"),
      state: state,
      city_name: city,
      county: county,
      town_name: if(is_town, do: city, else: nil),
      precinct_number: precinct,
      is_inside_city: is_city,
      city_council_district_code:
        if(is_city, do: Map.get(fields, "disclosures") |> get_local_ward(), else: nil),
      school_district_code: get_school_name(Map.get(fields, "school_districts", %{})),
      district_l1_code:
        get_in(fields, ["congressional_districts", Access.at(0), "district_number"]),
      district_l2_code:
        get_in(fields, ["state_legislative_districts", "senate", Access.at(0), "district_number"]),
      district_l3_code:
        get_in(fields, ["state_legislative_districts", "house", Access.at(0), "district_number"]),
      applicable_office_ids: final_applicable_ids
    }
  end

  def parse_boundaries(_), do: %{}

  # TEXAS JURISDICTION FILTER
  defp compute_state_specific_bounds(ids, "TX", _is_city, _is_town) do
    # All citizens vote for statewide & county judges. JP and Constable apply unconditionally per precinct grid.
    ids ++ ["tx_county_judge", "tx_constable", "tx_jp", "tx_ag_comm", "tx_rr_comm"]
  end

  # NEW YORK JURISDICTION FILTER (Town vs City Rule)
  defp compute_state_specific_bounds(ids, "NY", false, true) do
    # User is in an NY Town: Add Town Supervisor, avoid breaking city components
    ids ++ ["ny_town_supervisor", "ny_town_board"]
  end

  defp compute_state_specific_bounds(ids, "NY", true, false) do
    # User is in NYC/Buffalo City: Do not add town positions
    ids
  end

  # LOUISIANA PARISH FILTER
  defp compute_state_specific_bounds(ids, "LA", _, _) do
    ids ++ ["parish_president", "police_juror"]
  end

  # VIRGINIA INDEPENDENT CITY FILTER
  defp compute_state_specific_bounds(ids, "VA", _, _) do
    ids ++ ["va_comm_attorney", "va_comm_revenue"]
  end

  # NEW JERSEY SURROGATE FILTER
  defp compute_state_specific_bounds(ids, "NJ", _, _) do
    ids ++ ["nj_surrogate"]
  end

  # NEBRASKA UNICAMERAL SENATE FILTER
  defp compute_state_specific_bounds(ids, "NE", _, _) do
    ids ++ ["ne_unicameral_senator"]
  end

  defp compute_state_specific_bounds(ids, _, _, _), do: ids
end

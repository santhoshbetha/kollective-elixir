defmodule Kollective.Classifieds.Classifieds do
  @moduledoc """
  The Classifieds context for the town bulletin directory.
  Supports spatial distance searches utilizing PostGIS geom on PoliticalDistricts.
  """
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Kollective.Classifieds.Classified
  alias Kollective.Accounts.User
  alias Kollective.Locations.PoliticalDistrict
  alias Kollective.Locations.City

  @doc """
  Lists classifieds based on filter params (category, search, neighborhood, user_id, distance/scope).
  Only returns active and non-expired listings by default.
  If a distance/radius or local scope is requested, filters ads within search distance using PostGIS geom.
  """
  def list_classifieds(params \\ %{}, current_user \\ nil) do
    params = normalize_params(params)
    now = DateTime.utc_now()

    Classified
    |> filter_active(now, params["include_expired"])
    |> filter_context(params)
    |> filter_category(params["category"])
    |> filter_search(params["search"] || params["query"])
    |> filter_neighborhood(params["neighborhood"])
    |> filter_user(params["user_id"])
    |> filter_distance_or_scope(params, current_user)
    |> order_by([c], desc: c.inserted_at)
    |> preload([:user, :district, :organization])
    |> Repo.all()
  end

  @doc """
  Gets a single classified by ID.
  """
  def get_classified!(id) do
    Classified
    |> preload([:user, :district, :organization])
    |> Repo.get!(id)
  end

  @doc """
  Gets a single classified by ID or returns nil.
  """
  def get_classified(id) do
    Classified
    |> preload([:user, :district, :organization])
    |> Repo.get(id)
  end

  @doc """
  Creates a classified ad associated with the given user.
  - Automatically links the posting user's political district and its `geom` coordinates.
  - Enforces that the submitted email matches the user's profile email.
  - Persists organization_id when created in an organization context.
  """
  def create_classified(%User{} = user, attrs \\ %{}) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    district_id =
      attrs["district_id"] || user.district_l3_id || user.district_l2_id || user.district_l1_id

    district =
      if district_id do
        Repo.get(PoliticalDistrict, district_id)
      else
        nil
      end

    geom =
      cond do
        match?(%_{}, attrs["geom"]) ->
          attrs["geom"]

        is_binary(attrs["geom"]) and
            String.starts_with?(String.upcase(String.trim(attrs["geom"])), "POINT(") ->
          case Geo.WKT.decode(attrs["geom"]) do
            {:ok, pt} -> %{pt | srid: 4326}
            _ -> nil
          end

        true ->
          extract_user_geo(user, attrs) || (district && district.geom)
      end

    merged_attrs =
      attrs
      |> Map.put("user_id", user.id)
      |> Map.put("district_id", district_id)
      |> Map.put("geom", geom)

    merged_attrs =
      if attrs["organization_id"] do
        Map.put(merged_attrs, "organization_id", attrs["organization_id"])
      else
        merged_attrs
      end

    %Classified{}
    |> Classified.changeset(merged_attrs)
    |> validate_email_matches_user(user)
    |> Repo.insert()
    |> case do
      {:ok, classified} ->
        {:ok, Repo.preload(classified, [:user, :district, :organization])}

      error ->
        error
    end
  end

  @doc """
  Updates a classified ad.
  """
  def update_classified(%Classified{} = classified, attrs) do
    classified
    |> Classified.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        {:ok, Repo.preload(updated, [:user, :district])}

      error ->
        error
    end
  end

  @doc """
  Deletes a classified ad.
  """
  def delete_classified(%Classified{} = classified) do
    Repo.delete(classified)
  end

  # --- Internal Query & Validation Helpers ---

  defp validate_email_matches_user(changeset, %User{} = user) do
    user_email = String.downcase(String.trim(to_string(user.email || "")))
    submitted_email = Ecto.Changeset.get_field(changeset, :email)

    case submitted_email do
      nil ->
        changeset

      email ->
        if String.downcase(String.trim(to_string(email))) == user_email and user_email != "" do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :email,
            "must match the email address in your user profile"
          )
        end
    end
  end

  defp filter_context(query, %{"context" => "personal"}) do
    from(c in query, where: is_nil(c.organization_id))
  end

  defp filter_context(query, %{"context" => "organization", "organization_id" => org_id})
       when not is_nil(org_id) and org_id != "" do
    from(c in query, where: c.organization_id == ^org_id)
  end

  defp filter_context(query, %{"context" => "organization"}) do
    from(c in query, where: not is_nil(c.organization_id))
  end

  defp filter_context(query, %{"organization_id" => org_id})
       when not is_nil(org_id) and org_id != "" do
    from(c in query, where: c.organization_id == ^org_id)
  end

  defp filter_context(query, _), do: query

  defp filter_active(query, _now, true), do: query
  defp filter_active(query, _now, "true"), do: query

  defp filter_active(query, now, _include_expired) do
    from(c in query,
      where: c.status == "active" and c.expires_at > ^now
    )
  end

  defp filter_category(query, nil), do: query
  defp filter_category(query, ""), do: query
  defp filter_category(query, "All"), do: query
  defp filter_category(query, "all"), do: query

  defp filter_category(query, category) do
    from(c in query, where: ilike(c.category, ^category))
  end

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    pattern = "%#{search}%"

    from(c in query,
      where: ilike(c.title, ^pattern) or ilike(c.description, ^pattern)
    )
  end

  defp filter_neighborhood(query, nil), do: query
  defp filter_neighborhood(query, ""), do: query

  defp filter_neighborhood(query, neighborhood) do
    from(c in query, where: ilike(c.neighborhood, ^neighborhood))
  end

  defp filter_user(query, nil), do: query
  defp filter_user(query, ""), do: query

  defp filter_user(query, user_id) do
    from(c in query, where: c.user_id == ^user_id)
  end

  defp filter_distance_or_scope(query, params, current_user) do
    distance_param =
      params["distance"] ||
        params["radius"] ||
        params["distance_miles"] ||
        params["radius_miles"] ||
        params["radius_meters"]

    scope = params["scope"]

    has_coords? =
      (params["lat"] || params["latitude"]) &&
        (params["lng"] || params["lon"] || params["longitude"])

    if distance_param || scope in ["local", "distance"] || has_coords? do
      radius_meters = parse_classified_radius(params)
      origin_geo = extract_user_geo(current_user, params)

      origin_wkt =
        case origin_geo do
          %Geo.Point{} = point ->
            case Geo.WKT.encode(point) do
              {:ok, wkt} -> wkt
              _ -> nil
            end

          binary when is_binary(binary) ->
            binary

          _ ->
            nil
        end

      if origin_wkt do
        from(c in query,
          where:
            not is_nil(c.geom) and
              fragment(
                "ST_DWithin(ST_SetSRID(ST_Centroid(?), 4326)::geography, ST_SetSRID(ST_Centroid(ST_GeomFromText(?, 4326)), 4326)::geography, ?)",
                c.geom,
                ^origin_wkt,
                ^radius_meters
              )
        )
      else
        query
      end
    else
      if params["district_id"] && params["district_id"] != "" do
        from(c in query, where: c.district_id == ^params["district_id"])
      else
        query
      end
    end
  end

  @doc """
  Extracts the user's geographic point (%Geo.Point{}) hierarchically from:
    1. Explicit coordinates in `params_or_opts` (`lat`/`lng` or `latitude`/`longitude`).
    2. User's stored fuzzy coordinates in `user.location` (WKT or %Geo.Point{}).
    3. User's political district centroid (L3, L2, or L1 via `PoliticalDistrict.geom`).
    4. User's home city coordinates (via `City.latitude`/`City.longitude`).
    5. Fallback district in `params_or_opts["district_id"]`.
  """
  def extract_user_geo(user, params_or_opts \\ %{}) do
    params = normalize_params(params_or_opts)
    lat_param = params["lat"] || params["latitude"]
    lng_param = params["lng"] || params["lon"] || params["longitude"]

    cond do
      lat_param && lng_param ->
        with {:ok, lat} <- parse_coord(lat_param),
             {:ok, lng} <- parse_coord(lng_param) do
          %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        else
          _ -> extract_geo_from_user(user, params)
        end

      true ->
        extract_geo_from_user(user, params)
    end
  end

  defp extract_geo_from_user(%User{} = user, params) do
    cond do
      match?(%Geo.Point{}, user.location) ->
        %{user.location | srid: 4326}

      is_binary(user.location) and
          String.starts_with?(String.upcase(String.trim(user.location)), "POINT(") ->
        case Geo.WKT.decode(user.location) do
          {:ok, %Geo.Point{} = point} -> %{point | srid: 4326}
          _ -> fallback_user_geo_district_or_city(user, params)
        end

      is_binary(user.location) and String.contains?(user.location, ",") ->
        case String.split(user.location, ",") do
          [lat_s, lng_s] ->
            with {:ok, lat} <- parse_coord(String.trim(lat_s)),
                 {:ok, lng} <- parse_coord(String.trim(lng_s)) do
              %Geo.Point{coordinates: {lng, lat}, srid: 4326}
            else
              _ -> fallback_user_geo_district_or_city(user, params)
            end

          _ ->
            fallback_user_geo_district_or_city(user, params)
        end

      true ->
        fallback_user_geo_district_or_city(user, params)
    end
  end

  defp extract_geo_from_user(nil, params) do
    fallback_district_geo(params["district_id"])
  end

  defp fallback_user_geo_district_or_city(%User{} = user, params) do
    district_id =
      params["district_id"] ||
        user.district_l3_id || user.district_l2_id || user.district_l1_id

    district_geo = fallback_district_geo(district_id)
    district_geo || fallback_user_geo_city(user)
  end

  defp fallback_district_geo(nil), do: nil
  defp fallback_district_geo(""), do: nil

  defp fallback_district_geo(district_id) do
    case Repo.get(PoliticalDistrict, district_id) do
      %PoliticalDistrict{geom: %Geo.Point{coordinates: {lng, lat}}} ->
        %Geo.Point{coordinates: {lng, lat}, srid: 4326}

      %PoliticalDistrict{geom: %_{}} ->
        query =
          from d in PoliticalDistrict,
            where: d.id == ^district_id,
            select:
              {fragment("ST_Y(ST_Centroid(?))", d.geom), fragment("ST_X(ST_Centroid(?))", d.geom)}

        case Repo.one(query) do
          {lat, lng} when is_number(lat) and is_number(lng) ->
            %Geo.Point{coordinates: {lng, lat}, srid: 4326}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp fallback_user_geo_city(%User{} = user) do
    if user.city_id do
      case Repo.get(City, user.city_id) do
        %City{latitude: lat, longitude: lng}
        when not is_nil(lat) and not is_nil(lng) ->
          %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp parse_classified_radius(params) do
    meters = params["radius_meters"]

    miles =
      params["distance"] ||
        params["radius"] ||
        params["distance_miles"] ||
        params["radius_miles"]

    cond do
      meters ->
        case parse_coord(meters) do
          {:ok, r} -> r
          _ -> 25.0 * 1609.34
        end

      miles ->
        case parse_coord(miles) do
          {:ok, m} -> m * 1609.34
          _ -> 25.0 * 1609.34
        end

      true ->
        25.0 * 1609.34
    end
  end

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_params(params) when is_list(params) do
    Map.new(params, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_params(_), do: %{}

  defp parse_coord(nil), do: :error
  defp parse_coord(val) when is_float(val), do: {:ok, val}
  defp parse_coord(val) when is_integer(val), do: {:ok, val * 1.0}

  defp parse_coord(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> {:ok, num}
      _ -> :error
    end
  end

  defp parse_coord(_), do: :error
end

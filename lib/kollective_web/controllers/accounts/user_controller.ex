# lib/kollective_web/controllers/user_controller.ex
defmodule KollectiveWeb.UserController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Users
  alias Kollective.Accounts.Accounts
  alias Kollective.Locations.Locations

  # Fetches Service in prod, ServiceMock in test dynamically!
  @geo_client Application.compile_env(
                :kollective,
                :geospatial_client,
                Kollective.External.GeospatialService
              )

  # Delegated registration endpoint for standard REST POST /api/users
  defdelegate create(conn, params), to: KollectiveWeb.RegistrationController

  # GET /api/v1/me
  def me(conn, _params) do
    user = conn.assigns.current_user

    # Preload the 3 political tiers for the JSON view
    user = Users.load_user_districts(user)

    conn
    |> put_view(json: KollectiveWeb.UserJSON)
    |> render(:show, user: user)
  end

  # When the user clicks a tab (e.g., switching from "State" to "Local"), the React app hits an
  # endpoint to clear the badge for that specific user.
  def clear_feed_badge(conn, _params) do
    user = conn.assigns.current_user

    case Users.mark_feed_as_read(user) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "failed"})
    end
  end

  @doc """
  PATCH /api/v1/profile/districts
  Accepts an address payload string, uses the configured geospatial client
  to resolve official local boundary data, and applies updates to the user row.
  """
  def update_districts(conn, %{"address" => address} = params)
      when is_binary(address) and byte_size(address) > 0 do
    user = conn.assigns.current_user
    city = params["city"] || params["city_name"] || extract_city(address)
    street = extract_street(address)

    resolve_and_update_districts(conn, user, street, city)
  end

  def update_districts(conn, %{"street" => street} = params)
      when is_binary(street) and byte_size(street) > 0 do
    user = conn.assigns.current_user
    city = params["city"] || params["city_name"] || ""

    resolve_and_update_districts(conn, user, street, city)
  end

  def update_districts(conn, _) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing address parameter."})
  end

  defp resolve_and_update_districts(conn, user, street, city) do
    case @geo_client.geocode_us_address(street, city) do
      {:ok, geo_data} ->
        state = get_geo_field(geo_data, :state)
        lon = get_geo_field(geo_data, :lon)
        lat = get_geo_field(geo_data, :lat)
        district_label = get_geo_field(geo_data, :district)

        # Spatial lookup via PostGIS when coordinates are available
        {l1_dist, l2_dist, l3_dist} =
          if lon && lat do
            {
              Locations.find_district_by_coords(lon, lat, 1, "US"),
              Locations.find_district_by_coords(lon, lat, 2, "US"),
              Locations.find_district_by_coords(lon, lat, 3, "US")
            }
          else
            {nil, nil, nil}
          end

        l1_id = l1_dist && l1_dist.id
        l2_id = l2_dist && l2_dist.id
        l3_id = l3_dist && l3_dist.id

        l1_code =
          (l1_dist && (l1_dist.external_id || l1_dist.name)) || district_label || "1"

        l2_code = l2_dist && (l2_dist.external_id || l2_dist.name)
        l3_code = l3_dist && (l3_dist.external_id || l3_dist.name)

        fuzzy_location =
          case Accounts.fuzz_coordinates(lat, lon) do
            {:ok, _, _, wkt} -> wkt
            _ -> nil
          end

        district_params = %{
          "origin_state" => state,
          "district_l1" => l1_code,
          "district_l2" => l2_code,
          "district_l3" => l3_code,
          "district_l1_id" => l1_id,
          "district_l2_id" => l2_id,
          "district_l3_id" => l3_id,
          "location" => fuzzy_location,
          "street_address" => street
        }

        case Users.update_user_districts(user, district_params) do
          {:ok, updated_user} ->
            updated_user = Users.load_user_districts(updated_user)

            conn
            |> put_status(:ok)
            |> json(%{
              status: "success",
              message: "Political boundaries successfully synchronized.",
              user: KollectiveWeb.AccountJSON.show(%{user: updated_user, for: updated_user}),
              data: KollectiveWeb.AccountJSON.show(%{user: updated_user, for: updated_user})
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
        end

      {:error, :address_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Provided street address could not be located."})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "boundary_resolution_failed", message: reason})
    end
  end

  defp get_geo_field(geo_data, key) when is_map(geo_data) and is_atom(key) do
    Map.get(geo_data, key) || Map.get(geo_data, Atom.to_string(key))
  end

  defp get_geo_field(_, _), do: nil

  defp extract_street(address) do
    case String.split(address, ",") do
      [street | _] -> String.trim(street)
      _ -> String.trim(address)
    end
  end

  defp extract_city(address) do
    case String.split(address, ",") do
      [_, city | _] -> String.trim(city)
      _ -> ""
    end
  end

  # PATCH /api/v1/me/political-location
  def update_location(conn, %{"country" => "US", "street" => street} = params) do
    user = conn.assigns.current_user
    city = params["city_name"] || params["city"] || user.city_name
    city_id = params["city_id"] || user.city_id

    if city do
      # 1. Forward Geocode via our new Backend Elixir Service
      case @geo_client.geocode_us_address(street, city) do
        {:ok, geo_data} ->
          # 2. Pipe into our automated PostGIS boundary and caching pipeline
          location_params = %{
            "street" => street,
            "city_id" => city_id,
            "country" => "US",
            "state" => geo_data.state,
            "exact_lon" => geo_data.lon,
            "exact_lat" => geo_data.lat,
            "geocoder_metadata" => %{"county" => geo_data.county}
          }

          commit_location_update(conn, user, location_params)

        {:error, :address_not_found} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Provided street address could not be located."})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: reason})
      end
    else
      commit_location_update(conn, user, params)
    end
  end

  def update_location(conn, %{"country" => "IN"} = params) do
    user = conn.assigns.current_user
    lon = params["exact_lon"] || params["lng"] || params["longitude"]
    lat = params["exact_lat"] || params["lat"] || params["latitude"]

    if lon && lat do
      # 1. Reverse Geocode via our Backend Elixir Service to capture the timeline label string
      case @geo_client.reverse_geocode_coordinates(lon, lat) do
        {:ok, geo_data} ->
          # 2. Pass straight to the database intersection handlers
          location_params = %{
            "country" => "IN",
            "state" => geo_data.state,
            "exact_lon" => lon,
            "exact_lat" => lat,
            "geocoder_metadata" => %{"district" => geo_data.district}
          }

          commit_location_update(conn, user, location_params)

        {:error, reason} ->
          conn
          |> put_status(502)
          |> json(%{error: reason})
      end
    else
      commit_location_update(conn, user, params)
    end
  end

  # /api/v1/me/political-location/update-location
  # (when all attributes are passed from FE)
  def update_location(conn, attrs) do
    user = conn.assigns.current_user
    commit_location_update(conn, user, attrs)
  end

  defp commit_location_update(conn, user, params) do
    case Accounts.update_political_location(user, params) do
      {:ok, updated_user} ->
        updated_user = Users.load_user_districts(updated_user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Location updated successfully.",
          user: %{
            id: updated_user.id,
            street_address: updated_user.street_address,
            location: updated_user.location,
            country: updated_user.country,
            state: updated_user.state,
            state_updated_at: updated_user.state_updated_at,
            county: updated_user.county,
            city_id: updated_user.city_id,
            district_l1: if(updated_user.district_l1, do: updated_user.district_l1.name),
            district_l2: if(updated_user.district_l2, do: updated_user.district_l2.name),
            district_l3: if(updated_user.district_l3, do: updated_user.district_l3.name)
          }
        })

      {:error, :state_change_cooldown, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", error: "state_change_cooldown", message: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "location_update_failed", message: to_string(reason)})
    end
  end

  def delete_location(conn, _params) do
    user = conn.assigns.current_user

    case Accounts.clear_political_location(user) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Geographical footprint erased successfully.",
          user: %{
            id: updated_user.id,
            street_address: nil,
            country: updated_user.country,
            state: nil,
            county: nil,
            city_id: nil,
            district_l1: nil,
            district_l2: nil,
            district_l3: nil
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "location_clear_failed", message: reason})
    end
  end
end

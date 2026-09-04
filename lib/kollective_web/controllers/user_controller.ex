# lib/kollective_web/controllers/user_controller.ex
defmodule KollectiveWeb.UserController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Users
  alias Kollective.Accounts.Accounts
  alias Kollective.External.CivicService

  # Fetches Service in prod, ServiceMock in test dynamically!
  @geo_client Application.compile_env(
                :kollective,
                :geospatial_client,
                Kollective.External.GeospatialService
              )

  # GET /api/me
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
  Accepts a raw text address payload string, uses the external Google Civic API
  to resolve official local boundary data, and applies updates to the user row .
  """
  def update_districts(conn, %{"address" => address}) do
    # 1. Fetch the user profile struct straight out of RAM memory
    user = conn.assigns.current_user

    # 2. Fire the external lookup to extract political perimeters
    case CivicService.find_districts_by_address(address) do
      {:ok, civic_data} ->
        # Remap parsed key attributes to match your flat standalone user schema columns
        district_params = %{
          "origin_state" => civic_data.state,
          "district_l1" => civic_data.federal_district,
          "district_l2" => civic_data.state_senate_district,
          "district_l3" => civic_data.state_district
        }

        # 3. Write the resolved perimeters into the database row
        case Users.update_user_districts(user, district_params) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            # Modern Warning-Free Alternative: Serialize directly to json/2
            |> json(%{
              status: "success",
              message: "Political boundaries successfully synchronized.",
              data: KollectiveWeb.AccountJSON.show(%{user: updated_user, for: updated_user})
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "boundary_resolution_failed", message: reason})
    end
  end

  def update_districts(conn, _) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing address parameter."})
  end

  # PATCH /api/me/political-location
  def update_location(conn, %{"country" => "US", "street" => street} = params) do
    user = conn.assigns.current_user
    city = params["city_name"] || params["city"]
    city_id = params["city_id"]

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

  # /api/me/political-location/update-location
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
            country: updated_user.country,
            state: updated_user.state,
            county: updated_user.county,
            city_id: updated_user.city_id,
            district_l1: if(updated_user.district_l1, do: updated_user.district_l1.name),
            district_l2: if(updated_user.district_l2, do: updated_user.district_l2.name),
            district_l3: if(updated_user.district_l3, do: updated_user.district_l3.name)
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "location_update_failed", message: reason})
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

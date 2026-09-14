# test/kollective_web/controllers/user_location_test.exs
defmodule KollectiveWeb.UserLocationTest do
  use KollectiveWeb.ConnCase, async: true
  import Mox

  alias Kollective.Accounts.Accounts
  alias Kollective.Locations.City
  alias Kollective.Locations.PoliticalDistrict
  alias Kollective.Repo

  # Make sure Mox verifies that all expected mocks are evaluated during process cleanup
  setup :verify_on_exit!

  setup %{conn: conn} do
    l3_id = Ecto.ULID.generate()

    city =
      Repo.insert!(%City{
        name: "Austin",
        state: "TX",
        country: "US",
        external_id: "geoname_austin_101",
        latitude: 30.2672,
        longitude: -97.7431
      })

    geom = %Geo.Polygon{
      coordinates: [
        [
          {-97.8, 30.2},
          {-97.7, 30.2},
          {-97.7, 30.3},
          {-97.8, 30.3},
          {-97.8, 30.2}
        ]
      ],
      srid: 4326
    }

    _l1 =
      Repo.insert!(%PoliticalDistrict{
        id: Ecto.ULID.generate(),
        name: "US House District 10",
        level: 1,
        type_label: "Federal",
        country: "US",
        state: "TX",
        external_id: "TX-10",
        geom: geom
      })

    _l2 =
      Repo.insert!(%PoliticalDistrict{
        id: Ecto.ULID.generate(),
        name: "TX Senate District 14",
        level: 2,
        type_label: "State Upper",
        country: "US",
        state: "TX",
        external_id: "TX-SD-14",
        geom: geom
      })

    _l3 =
      Repo.insert!(%PoliticalDistrict{
        id: l3_id,
        name: "Austin Central Assembly",
        level: 3,
        type_label: "State Lower",
        country: "US",
        state: "TX",
        external_id: "TX-HD-Austin-Central",
        geom: geom
      })

    {:ok, user} =
      Accounts.register_user(%{
        "username" => "test_voter",
        "email" => "voter@kollective.org",
        "password" => "SuperSecretPassword123"
      })

    authed_conn = authenticate_conn(conn, user)
    {:ok, conn: authed_conn, user: user, city: city, expected_l3_id: l3_id}
  end

  describe "PATCH /api/me/political-location (Offline Mock Testing)" do
    test "successfully resolves districts using mocked GeoService responses", %{
      conn: conn,
      user: user,
      city: city,
      expected_l3_id: _expected_l3_id
    } do
      # INTERCEPT CONTEXT: Expect geocode_us_address to be called exactly 1 time
      # It intercepts the Req loop completely and mock returns a valid lat/lon map payload
      Kollective.Geospatial.ServiceMock
      |> expect(:geocode_us_address, 1, fn "123 Congress Ave", "Austin" ->
        {:ok,
         %{
           lat: 30.25,
           lon: -97.75,
           state: "TX",
           county: "Travis County",
           district: "Travis"
         }}
      end)

      payload = %{
        "country" => "US",
        "street" => "123 Congress Ave",
        "city_name" => "Austin",
        "city_id" => city.id
      }

      # This request executes 100% offline, ignoring the Nominatim API network servers!
      response =
        conn
        |> patch(~p"/api/me/political-location", payload)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["user"]["street_address"] == "123 Congress Ave"
      assert response["user"]["location"] == "POINT(-97.75 30.25)"
      assert response["user"]["state"] == "TX"
      assert response["user"]["district_l1"] == "US House District 10"
      assert response["user"]["district_l2"] == "TX Senate District 14"
      assert response["user"]["district_l3"] == "Austin Central Assembly"

      db_user = Repo.get!(Kollective.Accounts.User, user.id)
      assert db_user.location == "POINT(-97.75 30.25)"
    end
  end

  describe "PATCH /api/v1/profile/districts (Geospatial Service Mock Testing)" do
    test "successfully synchronizes districts using mocked @geo_client", %{
      conn: conn,
      user: user,
      expected_l3_id: expected_l3_id
    } do
      Kollective.Geospatial.ServiceMock
      |> expect(:geocode_us_address, 1, fn "123 Congress Ave", "Austin" ->
        {:ok,
         %{
           lat: 30.25,
           lon: -97.75,
           state: "TX",
           county: "Travis County",
           district: "Travis"
         }}
      end)

      payload = %{"address" => "123 Congress Ave, Austin"}

      response =
        conn
        |> patch(~p"/api/v1/profile/districts", payload)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] == "Political boundaries successfully synchronized."
      assert response["data"]["id"] == to_string(user.id)

      updated_user = Repo.get!(Kollective.Accounts.User, user.id)
      assert updated_user.origin_state == "TX"
      assert updated_user.district_l1_id != nil
      assert updated_user.district_l2_id != nil
      assert updated_user.district_l3_id == expected_l3_id
    end

    test "returns 422 when street address cannot be located", %{conn: conn} do
      Kollective.Geospatial.ServiceMock
      |> expect(:geocode_us_address, 1, fn "Nowhere Road", "Austin" ->
        {:error, :address_not_found}
      end)

      response =
        conn
        |> patch(~p"/api/v1/profile/districts", %{"address" => "Nowhere Road, Austin"})
        |> json_response(422)

      assert response["error"] =~ "could not be located"
    end

    test "returns 400 when address parameter is missing or blank", %{conn: conn} do
      response =
        conn
        |> patch(~p"/api/v1/profile/districts", %{})
        |> json_response(400)

      assert response["error"] == "Missing address parameter."

      blank_response =
        conn
        |> patch(~p"/api/v1/profile/districts", %{"address" => ""})
        |> json_response(400)

      assert blank_response["error"] == "Missing address parameter."
    end
  end
end

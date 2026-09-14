defmodule KollectiveWeb.ClassifiedControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Classifieds.Classifieds
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Scope
  alias Kollective.Repo

  alias Kollective.Locations.PoliticalDistrict

  setup do
    district =
      Repo.insert!(%PoliticalDistrict{
        name: "Austin Central L3",
        level: 3,
        type_label: "State Lower",
        state: "TX",
        country: "US",
        external_id: "TX-HD-49-#{System.unique_integer([:positive])}",
        geom: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
      })

    {:ok, user} =
      Repo.insert(%User{
        email: "ad_creator_#{System.unique_integer([:positive])}@test.com",
        username: "ad_poster_#{System.unique_integer([:positive])}",
        display_name: "Town Dispatcher",
        type: :citizen,
        district_l3_id: district.id
      })

    scope = Scope.for_user(user)

    valid_params = %{
      "title" => "Ergonomic Office Chair",
      "category" => "For Sale",
      "price" => "$60",
      "neighborhood" => "Midtown",
      "description" => "Adjustable mesh back chair. Excellent lumbar support.",
      "duration_days" => 7,
      "email" => user.email,
      "phone_number" => "555-0123"
    }

    %{user: user, district: district, scope: scope, valid_params: valid_params}
  end

  describe "GET /api/v1/classifieds" do
    test "lists active classified ads", %{
      conn: conn,
      user: user,
      district: district,
      valid_params: valid_params
    } do
      {:ok, ad} = Classifieds.create_classified(user, valid_params)

      conn = get(conn, ~p"/api/v1/classifieds")
      assert conn.status == 200
      response = json_response(conn, 200)

      assert is_list(response["classifieds"])
      assert length(response["classifieds"]) >= 1

      item = Enum.find(response["classifieds"], &(&1["id"] == to_string(ad.id)))
      assert item["title"] == "Ergonomic Office Chair"
      assert item["price"] == "$60"
      assert item["category"] == "For Sale"
      assert item["email"] == user.email
      assert item["phone_number"] == "555-0123"
      assert item["district_id"] == to_string(district.id)
      assert item["coordinates"] == %{"latitude" => 30.2672, "longitude" => -97.7431}
      # Frontend card accesses
      assert item["desc"] == "Adjustable mesh back chair. Excellent lumbar support."
      assert item["user"] == "@#{user.username}"
      assert item["location"] == "Midtown"
      assert item["expires"] =~ "days left"
    end

    test "filters classified ads by category and search", %{
      conn: conn,
      user: user,
      valid_params: valid_params
    } do
      {:ok, _} = Classifieds.create_classified(user, valid_params)

      conn = get(conn, ~p"/api/v1/classifieds?category=Services")
      response = json_response(conn, 200)
      assert response["classifieds"] == []

      conn = get(conn, ~p"/api/v1/classifieds?category=For+Sale")
      response = json_response(conn, 200)
      assert length(response["classifieds"]) >= 1
    end

    test "filters classified ads with user-chosen search distance", %{
      conn: conn,
      user: user,
      scope: scope,
      valid_params: valid_params
    } do
      {:ok, local_ad} = Classifieds.create_classified(user, valid_params)

      dallas_district =
        Repo.insert!(%PoliticalDistrict{
          name: "Dallas L3",
          level: 3,
          type_label: "State Lower",
          state: "TX",
          country: "US",
          external_id: "TX-DAL-#{System.unique_integer([:positive])}",
          geom: %Geo.Point{coordinates: {-96.7970, 32.7767}, srid: 4326}
        })

      {:ok, remote_user} =
        Repo.insert(%User{
          email: "dallas_#{System.unique_integer([:positive])}@test.com",
          username: "dallas_user_#{System.unique_integer([:positive])}",
          type: :citizen,
          district_l3_id: dallas_district.id
        })

      {:ok, remote_ad} =
        Classifieds.create_classified(remote_user, %{
          "title" => "Dallas Bike",
          "category" => "For Sale",
          "price" => "$120",
          "neighborhood" => "Deep Ellum",
          "description" => "Road bike in Dallas.",
          "email" => remote_user.email
        })

      # Local distance search within 25 miles excludes Dallas ad
      conn25 =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> get(~p"/api/v1/classifieds?distance=25")

      response25 = json_response(conn25, 200)
      ids25 = Enum.map(response25["classifieds"], & &1["id"])
      assert to_string(local_ad.id) in ids25
      refute to_string(remote_ad.id) in ids25

      # Broad search within 300 miles includes both ads
      conn300 =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> get(~p"/api/v1/classifieds?distance=300")

      response300 = json_response(conn300, 200)
      ids300 = Enum.map(response300["classifieds"], & &1["id"])
      assert to_string(local_ad.id) in ids300
      assert to_string(remote_ad.id) in ids300
    end

    test "filters classified ads using authenticated user's extracted fuzzy coordinates", %{
      conn: conn,
      scope: scope
    } do
      austin_user =
        Repo.insert!(%User{
          email: "austin_fuzzy_#{System.unique_integer([:positive])}@test.com",
          username: "austin_fuzzy_#{System.unique_integer([:positive])}",
          type: :citizen,
          location: "POINT(-97.75 30.25)"
        })

      {:ok, local_ad} =
        Classifieds.create_classified(austin_user, %{
          "title" => "Austin Handcrafted Lamp",
          "category" => "Handmade",
          "price" => "$60",
          "neighborhood" => "Zilker",
          "description" => "Handcrafted table lamp in Austin.",
          "email" => austin_user.email
        })

      dallas_user =
        Repo.insert!(%User{
          email: "dallas_remote_#{System.unique_integer([:positive])}@test.com",
          username: "dallas_remote_#{System.unique_integer([:positive])}",
          type: :citizen,
          location: "POINT(-96.80 32.78)"
        })

      {:ok, remote_ad} =
        Classifieds.create_classified(dallas_user, %{
          "title" => "Dallas Guitar",
          "category" => "For Sale",
          "price" => "$300",
          "neighborhood" => "Downtown Dallas",
          "description" => "Acoustic guitar.",
          "email" => dallas_user.email
        })

      conn25 =
        conn
        |> assign(:current_user, austin_user)
        |> assign(:current_scope, scope)
        |> get(~p"/api/v1/classifieds?distance=25")

      response25 = json_response(conn25, 200)
      ids25 = Enum.map(response25["classifieds"], & &1["id"])
      assert to_string(local_ad.id) in ids25
      refute to_string(remote_ad.id) in ids25
    end
  end

  describe "GET /api/v1/classifieds/:id" do
    test "shows classified ad details", %{
      conn: conn,
      user: user,
      district: district,
      valid_params: valid_params
    } do
      {:ok, ad} = Classifieds.create_classified(user, valid_params)

      conn = get(conn, ~p"/api/v1/classifieds/#{ad.id}")
      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["classified"]["id"] == to_string(ad.id)
      assert response["classified"]["title"] == "Ergonomic Office Chair"
      assert response["classified"]["email"] == user.email
      assert response["classified"]["phone_number"] == "555-0123"
      assert response["classified"]["district_id"] == to_string(district.id)

      assert response["classified"]["coordinates"] == %{
               "latitude" => 30.2672,
               "longitude" => -97.7431
             }

      assert response["classified"]["desc"] == ad.description
    end

    test "returns 404 for non-existent id", %{conn: conn} do
      fake_id = Ecto.ULID.generate()
      conn = get(conn, ~p"/api/v1/classifieds/#{fake_id}")
      assert conn.status == 404
    end
  end

  describe "POST /api/v1/classifieds and POST /classifieds" do
    test "creates classified when authenticated with nested classified param", %{
      conn: conn,
      user: user,
      district: district,
      scope: scope,
      valid_params: valid_params
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> post(~p"/api/v1/classifieds", %{"classified" => valid_params})

      assert conn.status == 201
      response = json_response(conn, 201)

      assert response["title"] == "Ergonomic Office Chair"
      assert response["desc"] == valid_params["description"]
      assert response["user"] == "@#{user.username}"
      assert response["email"] == user.email
      assert response["phone_number"] == "555-0123"
      assert response["district_id"] == to_string(district.id)
      assert response["coordinates"] == %{"latitude" => 30.2672, "longitude" => -97.7431}
      assert response["location"] == "Midtown"
      assert response["expires"] =~ "days left"
    end

    test "creates classified via unversioned /classifieds route", %{
      conn: conn,
      user: user,
      scope: scope,
      valid_params: valid_params
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> post("/classifieds", %{"classified" => valid_params})

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["title"] == "Ergonomic Office Chair"
      assert response["email"] == user.email
    end

    test "returns 401 when unauthenticated", %{conn: conn, valid_params: valid_params} do
      conn = post(conn, ~p"/api/v1/classifieds", %{"classified" => valid_params})
      assert conn.status == 401
    end

    test "returns 422 when email does not match user's profile email", %{
      conn: conn,
      user: user,
      scope: scope,
      valid_params: valid_params
    } do
      mismatched = Map.put(valid_params, "email", "imposter@domain.com")

      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> post(~p"/api/v1/classifieds", %{"classified" => mismatched})

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["errors"]["email"] != nil
    end

    test "returns 422 when params are invalid", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> post(~p"/api/v1/classifieds", %{"classified" => %{"title" => ""}})

      assert conn.status == 422
    end
  end

  describe "DELETE /api/v1/classifieds/:id" do
    test "allows owner to delete their ad", %{
      conn: conn,
      user: user,
      scope: scope,
      valid_params: valid_params
    } do
      {:ok, ad} = Classifieds.create_classified(user, valid_params)

      conn =
        conn
        |> assign(:current_user, user)
        |> assign(:current_scope, scope)
        |> delete(~p"/api/v1/classifieds/#{ad.id}")

      assert conn.status == 200
      assert json_response(conn, 200)["status"] == "success"
      assert Classifieds.get_classified(ad.id) == nil
    end

    test "returns 403 when non-owner tries to delete", %{
      conn: conn,
      user: user,
      valid_params: valid_params
    } do
      {:ok, other_user} =
        Repo.insert(%User{
          email: "other_#{System.unique_integer([:positive])}@test.com",
          username: "other_#{System.unique_integer([:positive])}",
          type: :citizen
        })

      other_scope = Scope.for_user(other_user)
      {:ok, ad} = Classifieds.create_classified(user, valid_params)

      conn =
        conn
        |> assign(:current_user, other_user)
        |> assign(:current_scope, other_scope)
        |> delete(~p"/api/v1/classifieds/#{ad.id}")

      assert conn.status == 403
    end
  end
end

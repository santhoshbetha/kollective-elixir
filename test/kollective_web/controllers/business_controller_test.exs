defmodule KollectiveWeb.BusinessControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  alias Kollective.Repo

  setup :authenticate_user

  setup %{conn: conn, user: user} do
    # Insert political district fixtures to satisfy database foreign keys
    l1 =
      Repo.insert!(%Kollective.Locations.PoliticalDistrict{
        name: "District L1",
        level: 1,
        type_label: "Federal",
        state: "CA",
        country: "US"
      })

    l2 =
      Repo.insert!(%Kollective.Locations.PoliticalDistrict{
        name: "District L2",
        level: 2,
        type_label: "State Upper",
        state: "CA",
        country: "US"
      })

    l3 =
      Repo.insert!(%Kollective.Locations.PoliticalDistrict{
        name: "District L3",
        level: 3,
        type_label: "State Lower",
        state: "CA",
        country: "US"
      })

    user =
      user
      |> Ecto.Changeset.change(%{
        state: "CA",
        location: "POINT(-118.2437 34.0522)",
        district_l1_id: l1.id,
        district_l2_id: l2.id,
        district_l3_id: l3.id
      })
      |> Repo.update!()

    conn = assign(conn, :current_user, user)
    {:ok, conn: conn, user: user}
  end

  describe "create business (POST /api/v1/businesses)" do
    test "successfully registers a business with valid parameters", %{conn: conn} do
      # Insert a city fixture so get_or_import_city does not hit external GeoNames API
      city = insert(:city)

      params = %{
        "business" => %{
          "name" => "Acme Cafe",
          "description" => "A cozy neighborhood coffee shop.",
          "category" => "food_beverage",
          "sub_category" => "cafe_coffee",
          "address" => "123 Main St",
          "city" => city.name,
          "state" => city.state,
          "zip" => "90001",
          "email" => "acme@cafe.com",
          "phone" => "213-555-0100",
          "legal_structure" => "LLC",
          "geoname_id" => city.external_id,
          "latitude" => 34.0522,
          "longitude" => -118.2437
        }
      }

      response =
        conn
        |> post(~p"/api/v1/businesses", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["message"] =~ "Verification is pending"
      assert response["data"]["name"] == "Acme Cafe"
      assert response["data"]["legal_structure"] == "LLC"
      assert response["data"]["id"]
    end

    test "normalizes frontend collaborative business form payload with flat params and display labels",
         %{conn: conn} do
      city = insert(:city)

      # Emulates payload sent directly from PostBusinessPage.jsx without "business" wrapper
      flat_params = %{
        "name" => "Eastside Solidarity Bakery & Farm",
        "description" =>
          "A community-owned worker cooperative providing organic bread and produce.",
        "category" => "Sustainable Energy",
        "legalStructure" => "Cooperative (Recommended)",
        "address" => "456 Solar Way",
        "city" => city.name,
        "state" => city.state,
        "zip" => "90002",
        "email" => "contact@solidarity.coop",
        "phone" => "213-555-0200",
        "website" => "solidarity.coop",
        "established" => "2024",
        "employees" => "1-5",
        "hours" => "8:00 AM - 4:00 PM",
        "image" => "https://images.unsplash.com/photo-solidarity.jpg",
        "services" => ["Worker-Owned", "Unionized Shop", "Solar Powered", "Local Sourcing"]
      }

      response =
        conn
        |> post(~p"/api/v1/businesses", flat_params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["name"] == "Eastside Solidarity Bakery & Farm"
      assert response["data"]["legal_structure"] == "Cooperative"
      assert response["data"]["hours"] == "8:00 AM - 4:00 PM"
      assert "Worker-Owned" in response["data"]["services"]
    end

    test "returns 422 with validation errors when parameters are invalid", %{conn: conn} do
      params = %{
        "business" => %{
          "name" => "",
          "category" => "invalid_category"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/businesses", params)
        |> json_response(422)

      assert response["errors"] || response["message"]
    end
  end

  describe "create business proposal (POST /api/v1/business_proposals)" do
    test "successfully registers a proposal with valid parameters", %{conn: conn} do
      params = %{
        "proposal" => %{
          "name" => "Community Tech Incubator",
          "description" => "A cooperative space to build and share tools.",
          "category" => "technology",
          "sub_category" => "software_saas",
          "funding_required" => true,
          "money_required" => 50000,
          "minimum_amount" => 100,
          "maximum_amount" => 5000
        }
      }

      response =
        conn
        |> post(~p"/api/v1/business_proposals", params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["message"] =~ "proposal has been successfully published"
      assert response["data"]["title"] == "Community Tech Incubator"
      assert response["data"]["category"] == "technology"
      assert response["data"]["funding_details"]["funding_required"] == true
    end

    test "normalizes frontend proposal payload with flat params and fundingGoal/minInvest", %{
      conn: conn
    } do
      flat_params = %{
        "title" => "Community Solar Microgrid Proposal",
        "description" =>
          "Neighborhood-owned solar array providing clean energy dividends to residents.",
        "category" => "Infrastructure",
        "location" => "Oakland District 4",
        "fundingGoal" => 75_000,
        "minInvest" => 50,
        "maxInvest" => 5000,
        "daysLeft" => 45,
        "participants" => "12 Members",
        "status" => "Active"
      }

      response =
        conn
        |> post(~p"/api/v1/business_proposals", flat_params)
        |> json_response(201)

      assert response["status"] == "success"
      assert response["data"]["title"] == "Community Solar Microgrid Proposal"
      assert response["data"]["fundingGoal"] == 75_000
      assert response["data"]["minInvest"] == 50
      assert response["data"]["maxInvest"] == 5000
      assert response["data"]["daysLeft"] == 45
      assert response["data"]["funding_details"]["funding_required"] == true
    end

    test "returns 422 with validation errors when proposal parameters are invalid", %{conn: conn} do
      params = %{
        "proposal" => %{
          "name" => ""
        }
      }

      response =
        conn
        |> post(~p"/api/v1/business_proposals", params)
        |> json_response(422)

      assert response["errors"] || response["message"]
    end
  end

  describe "list local businesses/proposals (GET /api/v1/businesses and /api/v1/business_proposals)" do
    setup %{conn: conn, user: user} do
      city = insert(:city)
      # Force user to belong to this city so they can discover items
      user = Repo.update!(Ecto.Changeset.change(user, city_id: city.id))
      conn = assign(conn, :current_user, user)

      business =
        insert(:business, user: user, city_relation: city, verification_status: "verified")

      proposal = insert(:business_proposal, user: user, city_relation: city)

      {:ok, conn: conn, user: user, city: city, business: business, proposal: proposal}
    end

    test "GET /api/v1/businesses returns verified existing businesses without type param", %{
      conn: conn,
      business: business
    } do
      response =
        conn
        |> get(~p"/api/v1/businesses")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert Enum.any?(response["data"], fn b -> b["name"] == business.name end)
    end

    test "GET /api/v1/businesses returns verified existing businesses", %{
      conn: conn,
      business: business
    } do
      response =
        conn
        |> get(~p"/api/v1/businesses", %{"type" => "existing"})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert Enum.any?(response["data"], fn b -> b["name"] == business.name end)
    end

    test "GET /api/v1/business_proposals returns proposal ideas without type param", %{
      conn: conn,
      proposal: proposal
    } do
      response =
        conn
        |> get(~p"/api/v1/business_proposals")
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert Enum.any?(response["data"], fn p -> p["name"] == proposal.name end)
    end

    test "GET /api/v1/business_proposals returns proposal ideas", %{
      conn: conn,
      proposal: proposal
    } do
      response =
        conn
        |> get(~p"/api/v1/business_proposals", %{"type" => "proposals"})
        |> json_response(200)

      assert response["status"] == "success"
      assert is_list(response["data"])
      assert Enum.any?(response["data"], fn p -> p["name"] == proposal.name end)
    end

    test "correctly discovers businesses within distance using extracted user coordinates and excludes distant ones",
         %{conn: conn, user: user} do
      # User with fuzzy coordinates in Austin (30.27, -97.74)
      # Clear city_id and districts so only physical distance matching applies
      austin_user =
        user
        |> Ecto.Changeset.change(%{
          city_id: nil,
          district_l1_id: nil,
          district_l2_id: nil,
          district_l3_id: nil,
          state: "TX",
          location: "POINT(-97.74 30.27)"
        })
        |> Repo.update!()

      # Business in Austin (~0 miles)
      _austin_biz =
        insert(:business,
          name: "Austin Coffee Roasters",
          verification_status: "verified",
          city_id: nil,
          district_l1: nil,
          district_l2: nil,
          district_l3: nil,
          state: "TX",
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
        )

      # Business in Round Rock (~15 miles away)
      _round_rock_biz =
        insert(:business,
          name: "Round Rock Bakery",
          verification_status: "verified",
          city_id: nil,
          district_l1: nil,
          district_l2: nil,
          district_l3: nil,
          state: "TX",
          location: %Geo.Point{coordinates: {-97.6789, 30.5083}, srid: 4326}
        )

      # Business in Dallas (~195 miles away - beyond 60 miles)
      _dallas_biz =
        insert(:business,
          name: "Dallas Steakhouse",
          verification_status: "verified",
          city_id: nil,
          district_l1: nil,
          district_l2: nil,
          district_l3: nil,
          state: "TX",
          location: %Geo.Point{coordinates: {-96.7970, 32.7767}, srid: 4326}
        )

      conn = assign(conn, :current_user, austin_user)

      # Default 60-mile radius: Austin & Round Rock included, Dallas excluded
      response =
        conn
        |> get(~p"/api/v1/businesses", %{"type" => "existing"})
        |> json_response(200)

      names = Enum.map(response["data"], & &1["name"])
      assert "Austin Coffee Roasters" in names
      assert "Round Rock Bakery" in names
      refute "Dallas Steakhouse" in names
    end

    test "filters businesses by coordinate distance along with category", %{
      conn: conn,
      user: user
    } do
      austin_user =
        user
        |> Ecto.Changeset.change(%{
          location: "POINT(-97.74 30.27)"
        })
        |> Repo.update!()

      _coffee =
        insert(:business,
          name: "Austin Espresso Hub",
          category: "food_beverage",
          verification_status: "verified",
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
        )

      _retail =
        insert(:business,
          name: "Austin Boutique Clothes",
          category: "retail",
          verification_status: "verified",
          location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
        )

      conn = assign(conn, :current_user, austin_user)

      response =
        conn
        |> get(~p"/api/v1/businesses", %{"type" => "existing", "category" => "food_beverage"})
        |> json_response(200)

      names = Enum.map(response["data"], & &1["name"])
      assert "Austin Espresso Hub" in names
      refute "Austin Boutique Clothes" in names
    end
  end

  describe "show business (GET /api/v1/businesses/:id)" do
    setup %{user: user} do
      business = insert(:business, user: user)
      proposal = insert(:business_proposal, user: user)
      {:ok, business: business, proposal: proposal}
    end

    test "returns detail view for existing business", %{conn: conn, business: business} do
      response =
        conn
        |> get(~p"/api/v1/businesses/#{business.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == to_string(business.id)
      assert response["data"]["type"] == "existing"
    end

    test "returns 404 when querying a proposal ID on the business endpoint", %{
      conn: conn,
      proposal: proposal
    } do
      response =
        conn
        |> get(~p"/api/v1/businesses/#{proposal.id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["message"] =~ "not found"
    end
  end

  describe "show proposal (GET /api/v1/business_proposals/:id)" do
    setup %{user: user} do
      business = insert(:business, user: user)
      proposal = insert(:business_proposal, user: user)
      {:ok, business: business, proposal: proposal}
    end

    test "returns detail view for proposal", %{conn: conn, proposal: proposal} do
      response =
        conn
        |> get(~p"/api/v1/business_proposals/#{proposal.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == to_string(proposal.id)
      assert response["data"]["type"] == "proposals"
    end

    test "returns 404 when querying a business ID on the proposal endpoint", %{
      conn: conn,
      business: business
    } do
      response =
        conn
        |> get(~p"/api/v1/business_proposals/#{business.id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["message"] =~ "not found"
    end
  end

  describe "update business (PUT /api/v1/businesses/:id)" do
    setup %{user: user} do
      business = insert(:business, user: user, verification_status: "verified")
      {:ok, business: business}
    end

    test "successfully updates own business with valid params", %{conn: conn, business: business} do
      params = %{
        "business" => %{
          "name" => "Acme Cafe Updated",
          "description" => "Our updated description."
        }
      }

      response =
        conn
        |> put(~p"/api/v1/businesses/#{business.id}", params)
        |> json_response(200)

      assert response["data"]["name"] == "Acme Cafe Updated"
    end

    test "returns 403 when updating a business owned by another user", %{conn: conn} do
      other_user = insert(:user)
      other_business = insert(:business, user: other_user)

      params = %{
        "business" => %{
          "name" => "Hijacked Store"
        }
      }

      response =
        conn
        |> put(~p"/api/v1/businesses/#{other_business.id}", params)
        |> json_response(403)

      assert response["error"] =~ "You are not the registered operator"
    end

    test "returns 422 when changing structural type of a verified business", %{
      conn: conn,
      business: business
    } do
      params = %{
        "business" => %{
          "type" => "proposals"
        }
      }

      response =
        conn
        |> put(~p"/api/v1/businesses/#{business.id}", params)
        |> json_response(422)

      assert response["error"] =~ "verified corporate profile cannot switch structural entity"
    end
  end

  describe "update proposal (PUT /api/v1/business_proposals/:id)" do
    setup %{user: user} do
      proposal = insert(:business_proposal, user: user)
      {:ok, proposal: proposal}
    end

    test "successfully updates own proposal with valid params", %{conn: conn, proposal: proposal} do
      params = %{
        "proposal" => %{
          "name" => "Incubator Updated",
          "description" => "Our updated description."
        }
      }

      response =
        conn
        |> put(~p"/api/v1/business_proposals/#{proposal.id}", params)
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["title"] == "Incubator Updated"
    end

    test "returns 403 when updating a proposal owned by another user", %{conn: conn} do
      other_user = insert(:user)
      other_proposal = insert(:business_proposal, user: other_user)

      params = %{
        "proposal" => %{
          "name" => "Hijacked Proposal"
        }
      }

      response =
        conn
        |> put(~p"/api/v1/business_proposals/#{other_proposal.id}", params)
        |> json_response(403)

      assert response["status"] == "error"
      assert response["message"] =~ "not authorized to edit this proposal"
    end
  end

  describe "delete business (DELETE /api/v1/businesses/:id)" do
    setup %{user: user} do
      business = insert(:business, user: user)
      {:ok, business: business}
    end

    test "successfully purges own business storefront", %{conn: conn, business: business} do
      response =
        conn
        |> delete(~p"/api/v1/businesses/#{business.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "cleanly purged"
    end

    test "returns 403 when deleting a business owned by another user", %{conn: conn} do
      other_user = insert(:user)
      other_business = insert(:business, user: other_user)

      response =
        conn
        |> delete(~p"/api/v1/businesses/#{other_business.id}")
        |> json_response(403)

      assert response["error"] =~ "Purge terminal rejected"
    end
  end

  describe "delete proposal (DELETE /api/v1/business_proposals/:id)" do
    setup %{user: user} do
      proposal = insert(:business_proposal, user: user)
      {:ok, proposal: proposal}
    end

    test "successfully retracts own business proposal", %{conn: conn, proposal: proposal} do
      response =
        conn
        |> delete(~p"/api/v1/business_proposals/#{proposal.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "successfully retracted"
    end

    test "returns 403 when deleting a proposal owned by another user", %{conn: conn} do
      other_user = insert(:user)
      other_proposal = insert(:business_proposal, user: other_user)

      response =
        conn
        |> delete(~p"/api/v1/business_proposals/#{other_proposal.id}")
        |> json_response(403)

      assert response["status"] == "error"
      assert response["message"] =~ "lack privileges to delete"
    end
  end
end

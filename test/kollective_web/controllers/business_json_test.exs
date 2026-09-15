defmodule KollectiveWeb.BusinessJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.User
  alias Kollective.Businesses.Business
  alias KollectiveWeb.BusinessJSON

  describe "BusinessJSON serialization" do
    setup do
      user = %User{
        id: 42,
        username: "johndoe",
        avatar_url: "https://example.com/avatar.png"
      }

      business = %Business{
        id: 101,
        name: "Acme Coffee",
        description: "Best coffee in town",
        type: "existing",
        category: "food_beverage",
        sub_category: "cafe_coffee",
        verification_status: "verified",
        upvotes_count: 15,
        comments_count: 3,
        address: "123 Main St",
        city: "Austin",
        state: "TX",
        zip: "78701",
        country: "US",
        email: "info@acme.com",
        phone: "512-555-0100",
        website: "https://acme.com",
        legal_structure: "LLC",
        year_established: 2020,
        number_of_employees: 10,
        profile_image_url: "https://example.com/profile.png",
        district_l1: "TX-10",
        district_l2: "TX-Senate-14",
        district_l3: "TX-House-46",
        location: %Geo.Point{coordinates: {-97.7431, 30.2672}},
        metadata: %{
          "business_hours" => %{"monday" => "9-5"},
          "funding_data" => %{"goal" => 10000}
        },
        inserted_at: ~U[2026-01-15 10:30:00Z],
        user: user
      }

      proposal = %Business{
        id: 102,
        name: "Solar Powered Bakery",
        type: "proposals",
        category: "technology",
        metadata: %{"funding_data" => %{"funding_required" => true, "money_required" => 50000}}
      }

      {:ok, user: user, business: business, proposal: proposal}
    end

    test "data/1 serializes full business entity", %{business: business} do
      data = BusinessJSON.data(business)

      assert data.id == "101"
      assert data.name == "Acme Coffee"
      assert data.type == "existing"
      assert data.category == "food_beverage"
      assert data.verification_status == "verified"
      assert data.legal_structure == "LLC"
      assert data.address == "123 Main St"
      assert data.city == "Austin"
      assert data.phone == "512-555-0100"
      assert data.email == "info@acme.com"
      assert data.website == "https://acme.com"
      assert data.location == "Austin"
      assert data.contact_details.city == "Austin"
      assert data.contact.city == "Austin"
      assert data.corporate_details.year_established == 2020
      assert data.metrics.year_established == 2020
      assert data.funding_details["goal"] == 10000
      assert data.geography.coordinates == %{longitude: -97.7431, latitude: 30.2672}
      assert data.owner == "johndoe"
      assert data.owner_info.username == "johndoe"
      assert data.inserted_at == "2026-01-15T10:30:00Z"
    end

    test "show/1 returns status success with data", %{business: business} do
      rendered = BusinessJSON.show(%{business: business})

      assert rendered.status == "success"
      assert rendered.data.name == "Acme Coffee"
    end

    test "index/1 serializes list of businesses", %{business: business} do
      items = BusinessJSON.index([business])

      assert length(items) == 1
      item = hd(items)
      assert item.id == "101"
      assert item.name == "Acme Coffee"
      assert item.owner.username == "johndoe"
    end

    test "leaderboard/1 serializes top ideas", %{business: business} do
      ideas = BusinessJSON.leaderboard([business])

      assert length(ideas) == 1
      idea = hd(ideas)
      assert idea.id == "101"
      assert idea.name == "Acme Coffee"
      assert idea.upvotes_count == 15
    end

    test "registration_data/1 serializes business registration info", %{business: business} do
      reg = BusinessJSON.registration_data(business)

      assert reg.id == "101"
      assert reg.name == "Acme Coffee"
      assert reg.legal_structure == "LLC"
      assert reg.business_hours["monday"] == "9-5"
    end

    test "proposal_data/1 serializes proposal info", %{proposal: proposal} do
      prop = BusinessJSON.proposal_data(proposal)

      assert prop.id == "102"
      assert prop.title == "Solar Powered Bakery"
      assert prop.category == "technology"
      assert prop.funding_details["funding_required"] == true
    end

    test "safely handles missing or not loaded user", %{business: business} do
      without_user = %{business | user: %Ecto.Association.NotLoaded{}}
      data = BusinessJSON.data(without_user)

      assert data.owner == "community_member"
      assert data.owner_info == nil
    end
  end
end

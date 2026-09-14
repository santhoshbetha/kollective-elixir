defmodule Kollective.ClassifiedsTest do
  use Kollective.DataCase, async: true

  alias Kollective.Classifieds.Classifieds
  alias Kollective.Classifieds.Classified
  alias Kollective.Accounts.User

  alias Kollective.Locations.PoliticalDistrict

  setup do
    district =
      Kollective.Repo.insert!(%PoliticalDistrict{
        name: "Central Austin L3",
        level: 3,
        type_label: "State Lower",
        state: "TX",
        country: "US",
        external_id: "TX-HD-49-#{System.unique_integer([:positive])}",
        geom: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326}
      })

    {:ok, user} =
      Kollective.Repo.insert(%User{
        email: "classified_user_#{System.unique_integer([:positive])}@test.com",
        username: "bulletin_fan_#{System.unique_integer([:positive])}",
        display_name: "Bulletin Poster",
        type: :citizen,
        district_l3_id: district.id
      })

    valid_attrs = %{
      "title" => "Co-op Fresh Eggs",
      "category" => "For Sale",
      "price" => "$4/doz",
      "neighborhood" => "East End",
      "description" => "Fresh organic eggs from our cage-free backyard coop. Collected daily.",
      "duration_days" => 7,
      "email" => user.email,
      "phone_number" => "555-0143"
    }

    %{user: user, district: district, valid_attrs: valid_attrs}
  end

  describe "create_classified/2 and get_classified/1" do
    test "successfully creates a classified ad with valid attributes and links district geom", %{
      user: user,
      district: district,
      valid_attrs: valid_attrs
    } do
      assert {:ok, %Classified{} = classified} = Classifieds.create_classified(user, valid_attrs)

      assert classified.title == "Co-op Fresh Eggs"
      assert classified.category == "For Sale"
      assert classified.price == "$4/doz"
      assert classified.neighborhood == "East End"
      assert classified.location == "East End"
      assert classified.status == "active"
      assert classified.user_id == user.id
      assert classified.user.username == user.username
      assert classified.email == user.email
      assert classified.phone_number == "555-0143"
      # Verifies political district and geom are linked
      assert classified.district_id == district.id
      assert classified.geom == district.geom
      assert classified.expires_at != nil
    end

    test "fails when submitted email does not match user's profile email", %{
      user: user,
      valid_attrs: valid_attrs
    } do
      invalid_email_attrs = Map.put(valid_attrs, "email", "imposter@other.com")

      assert {:error, changeset} = Classifieds.create_classified(user, invalid_email_attrs)

      assert %{email: ["must match the email address in your user profile"]} =
               errors_on(changeset)
    end

    test "fails with validation errors when missing required fields", %{user: user} do
      assert {:error, changeset} = Classifieds.create_classified(user, %{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
      assert %{price: ["can't be blank"]} = errors_on(changeset)
      assert %{neighborhood: ["can't be blank"]} = errors_on(changeset)
      assert %{description: ["can't be blank"]} = errors_on(changeset)
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_classifieds/2 with search distance" do
    test "filters classifieds by category, search query, and neighborhood", %{
      user: user,
      valid_attrs: valid_attrs
    } do
      {:ok, ad1} = Classifieds.create_classified(user, valid_attrs)

      {:ok, _ad2} =
        Classifieds.create_classified(user, %{
          "title" => "Math & Science Tutor",
          "category" => "Services",
          "price" => "$25/hr",
          "neighborhood" => "Heights",
          "description" => "High school and early college tutoring.",
          "duration_days" => 5,
          "email" => user.email
        })

      # Filter by category
      sale_ads = Classifieds.list_classifieds(%{"category" => "For Sale"})
      assert length(sale_ads) == 1
      assert hd(sale_ads).id == ad1.id

      # Filter by search
      search_ads = Classifieds.list_classifieds(%{"search" => "tutor"})
      assert length(search_ads) == 1
      assert hd(search_ads).title == "Math & Science Tutor"

      # Filter by neighborhood
      heights_ads = Classifieds.list_classifieds(%{"neighborhood" => "Heights"})
      assert length(heights_ads) == 1
      assert hd(heights_ads).neighborhood == "Heights"
    end

    test "filters classifieds by user-chosen search distance using district geom", %{
      user: user,
      valid_attrs: valid_attrs
    } do
      # Ad 1: Austin (user's district)
      {:ok, austin_ad} = Classifieds.create_classified(user, valid_attrs)

      # District 2: Round Rock (approx 15 miles north of Austin: -97.68, 30.50)
      round_rock_district =
        Kollective.Repo.insert!(%PoliticalDistrict{
          name: "Round Rock L3",
          level: 3,
          type_label: "State Lower",
          state: "TX",
          country: "US",
          external_id: "TX-RR-#{System.unique_integer([:positive])}",
          geom: %Geo.Point{coordinates: {-97.6789, 30.5083}, srid: 4326}
        })

      {:ok, rr_user} =
        Kollective.Repo.insert(%User{
          email: "rr_#{System.unique_integer([:positive])}@test.com",
          username: "rr_user_#{System.unique_integer([:positive])}",
          type: :citizen,
          district_l3_id: round_rock_district.id
        })

      {:ok, rr_ad} =
        Classifieds.create_classified(rr_user, %{
          "title" => "Round Rock Lawn Mower",
          "category" => "For Sale",
          "price" => "$80",
          "neighborhood" => "Downtown Round Rock",
          "description" => "Electric mower in great shape.",
          "email" => rr_user.email
        })

      # District 3: Dallas (approx 195 miles north of Austin: -96.7970, 32.7767)
      dallas_district =
        Kollective.Repo.insert!(%PoliticalDistrict{
          name: "Dallas L3",
          level: 3,
          type_label: "State Lower",
          state: "TX",
          country: "US",
          external_id: "TX-DAL-#{System.unique_integer([:positive])}",
          geom: %Geo.Point{coordinates: {-96.7970, 32.7767}, srid: 4326}
        })

      {:ok, dallas_user} =
        Kollective.Repo.insert(%User{
          email: "dal_#{System.unique_integer([:positive])}@test.com",
          username: "dal_user_#{System.unique_integer([:positive])}",
          type: :citizen,
          district_l3_id: dallas_district.id
        })

      {:ok, dallas_ad} =
        Classifieds.create_classified(dallas_user, %{
          "title" => "Dallas Road Bike",
          "category" => "For Sale",
          "price" => "$250",
          "neighborhood" => "Deep Ellum",
          "description" => "Carbon frame bike.",
          "email" => dallas_user.email
        })

      # 1. Search distance: 5 miles from user's Austin district -> only Austin ad
      ads_5_miles = Classifieds.list_classifieds(%{"distance" => "5"}, user)
      ids_5_miles = Enum.map(ads_5_miles, & &1.id)
      assert austin_ad.id in ids_5_miles
      refute rr_ad.id in ids_5_miles
      refute dallas_ad.id in ids_5_miles

      # 2. Search distance: 25 miles from user's Austin district -> Austin & Round Rock ads included, Dallas excluded
      ads_25_miles = Classifieds.list_classifieds(%{"distance" => "25"}, user)
      ids_25_miles = Enum.map(ads_25_miles, & &1.id)
      assert austin_ad.id in ids_25_miles
      assert rr_ad.id in ids_25_miles
      refute dallas_ad.id in ids_25_miles

      # 3. Search distance: 250 miles -> Austin, Round Rock, and Dallas ads all included
      ads_250_miles = Classifieds.list_classifieds(%{"distance" => "250"}, user)
      ids_250_miles = Enum.map(ads_250_miles, & &1.id)
      assert austin_ad.id in ids_250_miles
      assert rr_ad.id in ids_250_miles
      assert dallas_ad.id in ids_250_miles

      # 4. Search with custom lat/lng coordinates (e.g. searching around Round Rock directly)
      rr_coords_ads =
        Classifieds.list_classifieds(%{
          "lat" => "30.5083",
          "lng" => "-97.6789",
          "distance" => "10"
        })

      rr_ids = Enum.map(rr_coords_ads, & &1.id)
      assert rr_ad.id in rr_ids
      refute dallas_ad.id in rr_ids
    end

    test "uses extracted user fuzzy coordinates for ad creation and list_classifieds distance discovery" do
      fuzzy_user =
        Kollective.Repo.insert!(%User{
          email: "fuzzy_#{System.unique_integer([:positive])}@test.com",
          username: "fuzzy_#{System.unique_integer([:positive])}",
          type: :citizen,
          location: "POINT(-97.75 30.25)"
        })

      {:ok, local_ad} =
        Classifieds.create_classified(fuzzy_user, %{
          "title" => "Austin Handmade Pottery",
          "category" => "Handmade",
          "price" => "$45",
          "neighborhood" => "South Congress",
          "description" => "Handmade mugs in Austin.",
          "email" => fuzzy_user.email
        })

      assert %Geo.Point{coordinates: {-97.75, 30.25}} = local_ad.geom

      dallas_user =
        Kollective.Repo.insert!(%User{
          email: "dal_fuzzy_#{System.unique_integer([:positive])}@test.com",
          username: "dal_fuzzy_#{System.unique_integer([:positive])}",
          type: :citizen,
          location: "POINT(-96.80 32.78)"
        })

      {:ok, dallas_ad} =
        Classifieds.create_classified(dallas_user, %{
          "title" => "Dallas Antiques",
          "category" => "Handmade",
          "price" => "$150",
          "neighborhood" => "Downtown Dallas",
          "description" => "Vintage mirror.",
          "email" => dallas_user.email
        })

      # Search 25 miles from fuzzy_user's Austin location -> finds local_ad, excludes dallas_ad
      nearby_ads = Classifieds.list_classifieds(%{"distance" => "25"}, fuzzy_user)
      ids = Enum.map(nearby_ads, & &1.id)
      assert local_ad.id in ids
      refute dallas_ad.id in ids

      # Search with scope: "distance" (default 25 miles) -> also uses fuzzy_user coordinates
      scoped_ads = Classifieds.list_classifieds(%{"scope" => "distance"}, fuzzy_user)
      scoped_ids = Enum.map(scoped_ads, & &1.id)
      assert local_ad.id in scoped_ids
      refute dallas_ad.id in scoped_ids
    end
  end

  describe "delete_classified/1" do
    test "deletes the classified ad", %{user: user, valid_attrs: valid_attrs} do
      {:ok, ad} = Classifieds.create_classified(user, valid_attrs)
      assert {:ok, _} = Classifieds.delete_classified(ad)
      assert Classifieds.get_classified(ad.id) == nil
    end
  end
end

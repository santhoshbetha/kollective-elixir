defmodule KollectiveWeb.LocationJSONTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Locations.City
  alias KollectiveWeb.LocationJSON

  describe "LocationJSON serialization" do
    test "offices/1 serializes full office resolution payload" do
      payload = %{
        strategy_used: "pincode_exact",
        metadata: %{
          state: "Karnataka",
          county: "Bengaluru Urban",
          city: "Bengaluru",
          sub_district: "Bengaluru South",
          area_type: "urban",
          pincode: "560001",
          fallback_used: false,
          resolved_district: "Bengaluru Central",
          message: "Matched via ward database"
        },
        local_bodies: [
          %{
            id: 1,
            level: 4,
            name: "BBMP Ward 148",
            local_type: "Urban Local Body",
            area_type: "urban",
            lgd_code: 247_812
          }
        ],
        offices: [
          %{
            office_id: "corporator",
            category: "Urban Governance",
            title: "Municipal Corporator",
            scope: "city",
            desc: "Urban Ward",
            area_type: "urban",
            term_years: 5,
            qualifications: %{"min_age" => 21},
            run_note: "Must reside in ward"
          }
        ]
      }

      result = LocationJSON.offices(%{payload: payload})

      assert result.status == "success"
      assert result.strategy_used == "pincode_exact"
      assert result.metadata.state == "Karnataka"
      assert result.metadata.pincode == "560001"
      assert length(result.local_bodies) == 1
      assert hd(result.local_bodies).name == "BBMP Ward 148"
      assert length(result.offices) == 1

      office = hd(result.offices)
      assert office.office_id == "corporator"
      assert office.title == "Municipal Corporator"
      assert office.term_years == 5
      assert office.qualifications["min_age"] == 21
    end

    test "offices/1 supports bare map argument" do
      payload = %{
        strategy_used: "direct_lookup",
        metadata: %{city: "Austin"}
      }

      result = LocationJSON.offices(payload)
      assert result.status == "success"
      assert result.metadata.city == "Austin"
      assert result.local_bodies == []
      assert result.offices == []
    end

    test "cities/1 and city/1 serialize city search records" do
      city = %City{
        id: "01HXYZCITY0000000000000",
        name: "Austin",
        state: "TX",
        country: "US",
        latitude: 30.2672,
        longitude: -97.7431
      }

      result = LocationJSON.cities([city])
      assert length(result.data) == 1

      item = hd(result.data)
      assert item.id == "01HXYZCITY0000000000000"
      assert item.name == "Austin, TX"
      assert item.lat == 30.2672
      assert item.lon == -97.7431
    end

    test "districts/1 and district/1 serialize district suggestion payloads" do
      districts = [
        "ocd-division/country:us/state:tx/cd:10",
        "ocd-division/country:us/state:tx/sldl:46"
      ]

      result = LocationJSON.districts(districts)
      assert result.data == districts

      single = LocationJSON.district("ocd-division/country:us/state:tx/cd:10")
      assert single.data == "ocd-division/country:us/state:tx/cd:10"
    end
  end
end

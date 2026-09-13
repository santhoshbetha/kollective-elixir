defmodule Kollective.Locations.PoliticalDistrictSpatialTest do
  use Kollective.DataCase, async: true
  import Ecto.Query
  import Kollective.Factory
  import Kollective.Locations.SpatialQueries
  alias Kollective.Repo
  alias Kollective.Locations.PoliticalDistrict

  describe "PostGIS overlapping spatial layer lookups" do
    test "correctly resolves all 3 overlapping US political districts for a single user coordinate point" do
      # Create a shared boundary box where all 3 overlapping districts exist
      shared_bounding_box = %Geo.Polygon{
        coordinates: [
          [
            {-122.50, 37.70},
            {-122.35, 37.70},
            {-122.35, 37.85},
            {-122.50, 37.85},
            {-122.50, 37.70}
          ]
        ],
        srid: 4326
      }

      # Insert the three overlapping US layers for a user using the factory
      insert(:political_district,
        name: "California's 12th Congressional District",
        type_label: "Congressional",
        external_id: "CA-12",
        level: 1,
        country: "US",
        state: "CA",
        geom: shared_bounding_box
      )

      insert(:political_district,
        name: "State Senate District 11",
        type_label: "State Senate",
        external_id: "SD-11",
        level: 2,
        country: "US",
        state: "CA",
        geom: shared_bounding_box
      )

      insert(:political_district,
        name: "State Assembly District 19",
        type_label: "State Assembly",
        external_id: "AD-19",
        level: 3,
        country: "US",
        state: "CA",
        geom: shared_bounding_box
      )

      # A single voter's coordinate location (e.g., San Francisco) falling inside the boundaries
      user_point = %Geo.Point{coordinates: {-122.42, 37.77}, srid: 4326}

      # Query to extract all political layers for this user's position
      query =
        from d in PoliticalDistrict,
          where: d.country == "US" and st_contains(d.geom, ^user_point),
          order_by: [asc: d.level]

      results = Repo.all(query)

      # Verify that exactly three distinct layers are found for this single point coordinate
      assert length(results) == 3

      [congressional, senate, assembly] = results
      assert congressional.external_id == "CA-12"
      assert senate.external_id == "SD-11"
      assert assembly.external_id == "AD-19"
    end

    test "correctly resolves both overlapping Indian layers (Parliament and Assembly)" do
      shared_bounding_box = %Geo.Polygon{
        coordinates: [
          [
            {77.10, 28.55},
            {77.30, 28.55},
            {77.30, 28.70},
            {77.10, 28.70},
            {77.10, 28.55}
          ]
        ],
        srid: 4326
      }

      # India uses only 2 layers (Parliamentary vs Assembly Constituencies)
      insert(:political_district,
        name: "New Delhi Parliamentary Constituency",
        type_label: "Parliamentary",
        external_id: "DL-04",
        level: 1,
        country: "IN",
        geom: shared_bounding_box
      )

      insert(:political_district,
        name: "New Delhi Assembly Constituency",
        type_label: "Assembly",
        external_id: "AC-40",
        level: 2,
        country: "IN",
        geom: shared_bounding_box
      )

      user_point = %Geo.Point{coordinates: {77.20, 28.61}, srid: 4326}

      query =
        from d in PoliticalDistrict,
          where: d.country == "IN" and st_contains(d.geom, ^user_point),
          order_by: [asc: d.level]

      results = Repo.all(query)

      assert length(results) == 2
      [parliament, assembly] = results
      assert parliament.external_id == "DL-04"
      assert assembly.external_id == "AC-40"
    end
  end
end

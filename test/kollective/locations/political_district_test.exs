defmodule Kollective.Locations.PoliticalDistrictTest do
  use Kollective.DataCase, async: true
  alias Kollective.Locations.PoliticalDistrict

  describe "changeset/2 geometry parsing validation" do
    test "successfully validates a valid GeoJSON Polygon with SRID 4326" do
      # Mock geometry extracted directly from standard GIS outputs
      geojson_geometry = %{
        "type" => "Polygon",
        "coordinates" => [
          [[30.0, 10.0], [40.0, 40.0], [20.0, 40.0], [10.0, 20.0], [30.0, 10.0]]
        ]
      }

      native_geom =
        geojson_geometry
        |> Geo.JSON.decode!()
        |> Map.put(:properties, %{"srid" => 4326})

      valid_attrs = %{
        name: "Austin Congressional District",
        level: 1,
        country: "US",
        state: "TX",
        external_id: "TX-10",
        type_label: "Congressional District",
        geom: native_geom
      }

      changeset = PoliticalDistrict.changeset(%PoliticalDistrict{}, valid_attrs)

      assert changeset.valid?
      assert %Geo.Polygon{} = Ecto.Changeset.get_field(changeset, :geom)
    end

    test "fails validation if critical attributes or geometry structures are missing" do
      invalid_attrs = %{
        name: "Missing Coordinates District",
        level: 2,
        country: "IN"
        # Missing external_id and geom fields entirely
      }

      changeset = PoliticalDistrict.changeset(%PoliticalDistrict{}, invalid_attrs)

      refute changeset.valid?
      assert %{external_id: ["can't be blank"], geom: ["can't be blank"]} = errors_on(changeset)
    end
  end
end

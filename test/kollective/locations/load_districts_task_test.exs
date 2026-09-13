defmodule Kollective.Locations.LoadDistrictsTaskTest do
  use Kollective.DataCase, async: false
  alias Kollective.Locations.PoliticalDistrict
  alias Kollective.Repo

  @test_tmp_dir Path.join(
                  System.tmp_dir!(),
                  "load_districts_test_#{System.unique_integer([:positive])}"
                )

  setup do
    File.mkdir_p!(@test_tmp_dir)

    on_exit(fn ->
      File.rm_rf(@test_tmp_dir)
    end)

    :ok
  end

  describe "mix kollective.load_districts" do
    test "prints usage when called with wrong arguments" do
      assert :ok = Mix.Tasks.Kollective.LoadDistricts.run([])
      assert :ok = Mix.Tasks.Kollective.LoadDistricts.run(["some_file.json"])
    end

    test "handles non-existent file gracefully" do
      assert :ok =
               Mix.Tasks.Kollective.LoadDistricts.run([
                 Path.join(@test_tmp_dir, "does_not_exist.geojson"),
                 "US",
                 "1"
               ])
    end

    test "handles invalid level argument gracefully" do
      file = Path.join(@test_tmp_dir, "test.geojson")
      File.write!(file, "{}")

      assert :ok = Mix.Tasks.Kollective.LoadDistricts.run([file, "US", "invalid"])
      assert :ok = Mix.Tasks.Kollective.LoadDistricts.run([file, "US", "5"])
    end

    test "successfully imports standard GeoJSON with parent hierarchy" do
      # 1. First insert a parent district in the DB
      parent =
        Repo.insert!(%PoliticalDistrict{
          name: "California",
          level: 1,
          country: "US",
          state: "CA",
          external_id: "STATE-CA",
          type_label: "State",
          geom: %Geo.Polygon{
            coordinates: [
              [{-124.0, 32.0}, {-114.0, 32.0}, {-114.0, 42.0}, {-124.0, 42.0}, {-124.0, 32.0}]
            ],
            srid: 4326
          }
        })

      # 2. Prepare a GeoJSON with a child pointing to STATE-CA as parent_id
      geojson = %{
        "type" => "FeatureCollection",
        "features" => [
          %{
            "type" => "Feature",
            "properties" => %{
              "GEOID" => "CA-12",
              "NAMELSAD" => "Congressional District 12",
              "STATE" => "CA",
              "TYPE" => "Congressional",
              "parent_id" => "STATE-CA"
            },
            "geometry" => %{
              "type" => "Polygon",
              "coordinates" => [
                [
                  [-122.50, 37.70],
                  [-122.35, 37.70],
                  [-122.35, 37.85],
                  [-122.50, 37.85],
                  [-122.50, 37.70]
                ]
              ]
            }
          }
        ]
      }

      file_path = Path.join(@test_tmp_dir, "districts.geojson")
      File.write!(file_path, Jason.encode!(geojson))

      Mix.Tasks.Kollective.LoadDistricts.run([file_path, "us", "2"])

      imported = Repo.get_by(PoliticalDistrict, external_id: "CA-12", country: "US")
      assert imported != nil
      assert imported.name == "Congressional District 12"
      assert imported.state == "CA"
      assert imported.type_label == "Congressional"
      assert imported.level == 2
      assert imported.parent_id == parent.id
      assert %Geo.Polygon{srid: 4326} = imported.geom
    end

    test "successfully imports streaming GeoJSONL and performs upsert on conflict" do
      line1 =
        Jason.encode!(%{
          "type" => "Feature",
          "properties" => %{
            "id" => "DL-01",
            "name" => "Chandni Chowk",
            "state" => "Delhi"
          },
          "geometry" => %{
            "type" => "Polygon",
            "coordinates" => [
              [[77.15, 28.60], [77.25, 28.60], [77.25, 28.70], [77.15, 28.70], [77.15, 28.60]]
            ]
          }
        })

      file_path = Path.join(@test_tmp_dir, "districts.geojsonl")
      File.write!(file_path, line1 <> "\n")

      # First run inserts
      Mix.Tasks.Kollective.LoadDistricts.run([file_path, "IN", "1"])

      first_record = Repo.get_by(PoliticalDistrict, external_id: "DL-01", country: "IN")
      assert first_record != nil
      assert first_record.name == "Chandni Chowk"
      assert first_record.type_label == "Parliamentary"

      # Second run updates
      line1_updated =
        Jason.encode!(%{
          "type" => "Feature",
          "properties" => %{
            "id" => "DL-01",
            "name" => "Chandni Chowk Parliamentary",
            "state" => "Delhi"
          },
          "geometry" => %{
            "type" => "Polygon",
            "coordinates" => [
              [[77.15, 28.60], [77.25, 28.60], [77.25, 28.70], [77.15, 28.70], [77.15, 28.60]]
            ]
          }
        })

      File.write!(file_path, line1_updated <> "\n")
      Mix.Tasks.Kollective.LoadDistricts.run([file_path, "IN", "1"])

      updated_record = Repo.get_by(PoliticalDistrict, external_id: "DL-01", country: "IN")
      assert updated_record.id == first_record.id
      assert updated_record.name == "Chandni Chowk Parliamentary"
    end
  end
end

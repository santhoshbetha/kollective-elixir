defmodule Kollective.Services.GeocodioClientTest do
  use Kollective.DataCase, async: true
  alias Kollective.Services.GeocodioClient

  describe "parse_boundaries/1" do
    test "successfully parses Geocodio payload with city and school district in TX" do
      payload = %{
        "results" => [
          %{
            "formatted_address" => "1106 Congress Ave, Austin, TX 78701",
            "address_components" => %{
              "type" => "city",
              "county" => "Travis County",
              "city" => "Austin",
              "state" => "TX"
            },
            "fields" => %{
              "congressional_districts" => [
                %{"district_number" => "10"}
              ],
              "state_legislative_districts" => %{
                "senate" => [%{"district_number" => "14"}],
                "house" => [%{"district_number" => "46"}]
              },
              "school_districts" => %{
                "unified" => %{"name" => "Austin ISD"}
              },
              "disclosures" => %{
                "local_jurisdiction" => %{
                  "district" => "District 9"
                }
              }
            }
          }
        ]
      }

      parsed = GeocodioClient.parse_boundaries(payload)

      assert parsed.street_address == "1106 Congress Ave, Austin, TX 78701"
      assert parsed.county == "Travis County"
      assert parsed.city_council_district_code == "District 9"
      assert parsed.school_district_code == "Austin ISD"
      assert parsed.district_l1_code == "10"
      assert parsed.district_l2_code == "14"
      assert parsed.district_l3_code == "46"

      # Verify applicable office IDs contain general, city-specific, school-specific, and TX state-specific IDs
      assert "governor" in parsed.applicable_office_ids
      assert "mayor" in parsed.applicable_office_ids
      assert "city_council" in parsed.applicable_office_ids
      assert "school_board" in parsed.applicable_office_ids
      assert "tx_county_judge" in parsed.applicable_office_ids
    end

    test "handles unincorporated area without municipal boundaries or school district" do
      payload = %{
        "results" => [
          %{
            "formatted_address" => "Rural Road, Unincorporated, TX 75001",
            "address_components" => %{
              "type" => "unincorporated",
              "county" => "Some County",
              "state" => "TX"
            },
            "fields" => %{
              "congressional_districts" => [
                %{"district_number" => "4"}
              ],
              "state_legislative_districts" => %{
                "senate" => [%{"district_number" => "2"}],
                "house" => [%{"district_number" => "8"}]
              }
            }
          }
        ]
      }

      parsed = GeocodioClient.parse_boundaries(payload)

      assert parsed.street_address == "Rural Road, Unincorporated, TX 75001"
      assert parsed.county == "Some County"
      assert is_nil(parsed.city_council_district_code)
      assert is_nil(parsed.school_district_code)
      assert parsed.district_l1_code == "4"
      assert parsed.district_l2_code == "2"
      assert parsed.district_l3_code == "8"

      # Unincorporated: should not have city or school board office ids
      refute "mayor" in parsed.applicable_office_ids
      refute "city_council" in parsed.applicable_office_ids
      refute "school_board" in parsed.applicable_office_ids
      assert "governor" in parsed.applicable_office_ids
      assert "tx_county_judge" in parsed.applicable_office_ids
    end
  end
end

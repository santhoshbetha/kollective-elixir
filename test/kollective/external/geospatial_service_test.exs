defmodule Kollective.External.GeospatialServiceTest do
  use ExUnit.Case, async: false
  alias Kollective.External.GeospatialService
  alias Kollective.External.GeospatialTestProvider

  setup do
    original_config = Application.get_env(:kollective, GeospatialService)
    Application.put_env(:kollective, GeospatialService, service: GeospatialTestProvider)

    on_exit(fn ->
      if original_config do
        Application.put_env(:kollective, GeospatialService, original_config)
      else
        Application.delete_env(:kollective, GeospatialService)
      end

      Process.delete({GeospatialTestProvider, :search_result})
      Process.delete({GeospatialTestProvider, :geocode_result})
    end)

    :ok
  end

  describe "service/0" do
    test "returns configured service module" do
      assert GeospatialService.service() == GeospatialTestProvider
    end
  end

  describe "geocode_us_address/2" do
    test "successfully resolves structured street and city address with Address struct" do
      {:ok, result} = GeospatialService.geocode_us_address("1106 Congress Ave", "Austin")

      assert result.lat == 30.2672
      assert result.lon == -97.7431
      assert result.state == "Texas"
      assert result.county == "Austin"
      assert result.district == "Austin"
    end

    test "handles raw map payload with string keys and string lat/lon" do
      Process.put(
        {GeospatialTestProvider, :search_result},
        [
          %{
            "lat" => "37.7749",
            "lon" => "-122.4194",
            "address" => %{
              "state" => "California",
              "county" => "San Francisco County",
              "suburb" => "Downtown"
            }
          }
        ]
      )

      {:ok, result} = GeospatialService.geocode_us_address("Market St", "San Francisco")

      assert result.lat == 37.7749
      assert result.lon == -122.4194
      assert result.state == "California"
      assert result.county == "San Francisco County"
      assert result.district == "Downtown"
    end

    test "handles integer lat/lon values safely without crashing" do
      Process.put(
        {GeospatialTestProvider, :search_result},
        [
          %{
            "lat" => 40,
            "lon" => -74,
            "address" => %{
              "state" => "New York",
              "county" => "New York County"
            }
          }
        ]
      )

      {:ok, result} = GeospatialService.geocode_us_address("5th Ave", "New York")

      assert result.lat == 40.0
      assert result.lon == -74.0
      assert result.state == "New York"
    end

    test "returns address_not_found error when no results match" do
      Process.put({GeospatialTestProvider, :search_result}, [])

      assert GeospatialService.geocode_us_address("Nonexistent St", "Nowhere") ==
               {:error, :address_not_found}
    end

    test "returns formatted network error when provider returns error tuple" do
      Process.put({GeospatialTestProvider, :search_result}, {:error, "Connection timeout"})

      assert {:error, msg} = GeospatialService.geocode_us_address("123 Main St", "Austin")
      assert msg =~ "Connection timeout"
    end
  end

  describe "reverse_geocode_coordinates/2" do
    test "successfully resolves coordinates into location metadata" do
      {:ok, result} = GeospatialService.reverse_geocode_coordinates(-97.7431, 30.2672)

      assert result.lat == 30.2672
      assert result.lon == -97.7431
      assert result.state == "Texas"
      assert result.county == "Travis County"
    end

    test "returns address_not_found error when reverse lookup returns empty list" do
      Process.put({GeospatialTestProvider, :geocode_result}, [])

      assert GeospatialService.reverse_geocode_coordinates(0.0, 0.0) ==
               {:error, :address_not_found}
    end
  end
end

defmodule Kollective.External.GeospatialTestProvider do
  @moduledoc false

  def search(query, _params) do
    Process.get({__MODULE__, :search_result, query}) ||
      Process.get({__MODULE__, :search_result}) ||
      [
        %Geospatial.Address{
          geom: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326},
          region: "Texas",
          locality: "Austin",
          country: "United States",
          street: "1106 Congress Ave"
        }
      ]
  end

  def geocode(lon, lat, _params) do
    Process.get({__MODULE__, :geocode_result, {lon, lat}}) ||
      Process.get({__MODULE__, :geocode_result}) ||
      [
        %Geospatial.Address{
          geom: %Geo.Point{coordinates: {lon, lat}, srid: 4326},
          region: "Texas",
          locality: "Travis County",
          country: "United States"
        }
      ]
  end
end

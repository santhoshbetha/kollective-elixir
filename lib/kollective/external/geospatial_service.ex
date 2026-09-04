defmodule Kollective.External.GeospatialService do
  @moduledoc """
  High-level proxy layer coordinating geospatial operations dynamically.
  """

  @behaviour Kollective.Geospatial.Behaviour

  # Fetches the runtime active module provider from your config files dynamically
  def service do
    Application.get_env(:kollective, __MODULE__)[:service] ||
      get_in(Application.get_env(:geospatial, Geospatial.Service), [:service]) ||
      Geospatial.Providers.Nominatim
  end

  @doc """
  Performs forward geocoding for a structured US street address via config-driven providers.
  """
  def geocode_us_address(street, city) do
    query =
      [street, city, "US"]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(", ")

    params = [
      limit: 1,
      country_code: "us"
    ]

    dispatch_search(query, params)
  end

  @doc """
  Performs reverse geocoding for coordinates to capture casual timeline text labels.
  """
  def reverse_geocode_coordinates(lon, lat) do
    params = [
      addressdetails: 1,
      format: "jsonv2"
    ]

    dispatch_geocode(lon, lat, params)
  end

  defp dispatch_search(query, params) do
    svc = service()
    Code.ensure_loaded(svc)

    result =
      cond do
        function_exported?(svc, :search, 2) ->
          svc.search(query, params)

        function_exported?(svc, :search, 1) ->
          svc.search(query)

        true ->
          {:error, :unsupported_provider}
      end

    handle_response(result)
  rescue
    e in [FunctionClauseError, UndefinedFunctionError] ->
      {:error, "Geospatial service provider error: #{inspect(e)}"}

    e ->
      {:error, "Geospatial service provider network error: #{inspect(e)}"}
  end

  defp dispatch_geocode(lon, lat, params) do
    svc = service()
    Code.ensure_loaded(svc)

    result =
      cond do
        function_exported?(svc, :geocode, 3) ->
          svc.geocode(lon, lat, params)

        function_exported?(svc, :geocode, 2) ->
          try do
            svc.geocode(lon, lat)
          rescue
            _ -> svc.geocode(%{lon: lon, lat: lat}, params)
          end

        true ->
          {:error, :unsupported_provider}
      end

    handle_response(result)
  rescue
    e in [FunctionClauseError, UndefinedFunctionError] ->
      {:error, "Geospatial service reverse error: #{inspect(e)}"}

    e ->
      {:error, "Geospatial service reverse network error: #{inspect(e)}"}
  end

  # Standardizes payload shapes so your controllers get uniform data structures
  defp handle_response(result) do
    case result do
      {:ok, [%Geospatial.Address{} = top_result | _]} ->
        {:ok, parse_payload(top_result)}

      {:ok, [top_result | _]} when is_map(top_result) ->
        {:ok, parse_payload(top_result)}

      {:ok, %Geospatial.Address{} = top_result} ->
        {:ok, parse_payload(top_result)}

      {:ok, top_result} when is_map(top_result) ->
        {:ok, parse_payload(top_result)}

      [%Geospatial.Address{} = top_result | _] ->
        {:ok, parse_payload(top_result)}

      [top_result | _] when is_map(top_result) ->
        {:ok, parse_payload(top_result)}

      %Geospatial.Address{} = top_result ->
        {:ok, parse_payload(top_result)}

      {:ok, []} ->
        {:error, :address_not_found}

      [] ->
        {:error, :address_not_found}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Geospatial service provider error: #{inspect(reason)}"}

      _ ->
        {:error, :address_not_found}
    end
  end

  defp parse_payload(%Geospatial.Address{} = addr) do
    {lon, lat} =
      case addr.geom do
        %Geo.Point{coordinates: {lon_val, lat_val}} -> {lon_val, lat_val}
        _ -> {nil, nil}
      end

    %{
      lat: ensure_float(lat),
      lon: ensure_float(lon),
      state: addr.region,
      county: addr.locality,
      district: addr.locality
    }
  end

  defp parse_payload(body) when is_map(body) do
    addr = body["address"] || body[:address] || %{}

    lat = body["lat"] || body[:lat]
    lon = body["lon"] || body[:lon]

    state = addr["state"] || addr[:state] || body["state"] || body[:state]
    county = addr["county"] || addr[:county] || body["county"] || body[:county]

    district =
      addr["district"] || addr[:district] ||
        addr["suburb"] || addr[:suburb] ||
        county || body["district"] || body[:district]

    %{
      lat: ensure_float(lat),
      lon: ensure_float(lon),
      state: state,
      county: county,
      district: district
    }
  end

  # Defensive parsing helper since different high-level providers return floats, integers or strings
  defp ensure_float(nil), do: nil
  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1.0

  defp ensure_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp ensure_float(_), do: nil
end

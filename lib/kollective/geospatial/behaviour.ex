defmodule Kollective.Geospatial.Behaviour do
  @moduledoc """
  Behaviour contract for Geospatial services (geocoding and reverse geocoding).

  In Elixir @callback directives are used to define a contract.
  Mox cannot mimic a module unless it has defined behaviors.
  """

  @callback geocode_us_address(street :: String.t(), city :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback reverse_geocode_coordinates(
              lon :: number() | String.t(),
              lat :: number() | String.t()
            ) ::
              {:ok, map()} | {:error, term()}
end

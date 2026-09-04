defmodule Kollective.Governance.LocationStrategy do
  @moduledoc """
  Defines the common interface for processing multi-country address lookups.
  """

  # Unified normalized structure returned to the core lookup module
  @type location_context :: %{
          state: String.t(),
          county: String.t() | nil,
          city: String.t() | nil,
          sub_district: String.t() | nil
        }

  @callback fetch_context(address :: String.t()) :: {:ok, location_context()} | {:error, any()}
end

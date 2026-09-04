defmodule Kollective.Governance.LocationFactory do
  alias Kollective.Governance.Strategies.USStrategy

  @doc """
  Dynamic lookup switch factory choosing drivers by country code.
  """
  def get_strategy("US"), do: {:ok, USStrategy}

  # Default Fallback Strategy if a specific country driver hasn't been coded yet
  def get_strategy(_other_country), do: {:ok, USStrategy}
end

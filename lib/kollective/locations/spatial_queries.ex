defmodule Kollective.Locations.SpatialQueries do
  @moduledoc """
  Custom Ecto API macros wrapping common PostGIS spatial functions.
  """

  @doc """
  Returns true if geometry A completely contains geometry B.
  """
  defmacro st_contains(geom_a, geom_b) do
    quote do
      fragment("ST_Contains(?, ?)", unquote(geom_a), unquote(geom_b))
    end
  end

  @doc """
  Returns true if geometry A is within geometry B.
  """
  defmacro st_within(geom_a, geom_b) do
    quote do
      fragment("ST_Within(?, ?)", unquote(geom_a), unquote(geom_b))
    end
  end

  @doc """
  Calculates the minimum distance between two geometries in degrees or meters.
  """
  defmacro st_distance(geom_a, geom_b) do
    quote do
      fragment("ST_Distance(?, ?)", unquote(geom_a), unquote(geom_b))
    end
  end
end

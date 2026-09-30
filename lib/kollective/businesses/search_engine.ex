defmodule Kollective.Businesses.SearchEngine do
  @moduledoc """
  ⚡ GEOSPATIAL SEARCH ENGINE LAYERS
  Executes high-performance PostGIS distance lookups, category slicing,
  and geometric viewport bounding box checks against the businesses schema.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Businesses.Business

  #  MASTER SEARCH METRIC CONSTRUCTOR
  #  Accepts optional maps containing text filters, categories, bounds, or coordinate radius pins
  def search_businesses(filters \\ %{}) do
    Business
    |> preload([:user])
    |> filter_by_type(filters)
    |> filter_by_category_and_sub(filters)
    |> filter_by_search_term(filters)
    |> filter_by_geofence(filters)
    |> order_by_metrics(filters)
    |> Repo.all()
  end

  # 1 Isolate "proposals" from "existing" storefront nodes
  defp filter_by_type(query, %{"type" => type}) when type in ["proposals", "existing"] do
    from(b in query, where: b.type == ^type)
  end

  defp filter_by_type(query, _), do: query

  # 2 Fast text array inclusion checks for classifications
  defp filter_by_category_and_sub(query, %{"category" => cat, "sub_category" => sub})
       when sub != "" and cat != "" do
    from(b in query, where: b.category == ^cat and b.sub_category == ^sub)
  end

  defp filter_by_category_and_sub(query, %{"category" => cat}) when cat != "" do
    from(b in query, where: b.category == ^cat)
  end

  defp filter_by_category_and_sub(query, _), do: query

  # 3 Full-Text Fuzzy String Search fallback matching
  defp filter_by_search_term(query, %{"q" => term}) when is_binary(term) and term != "" do
    pattern = "%#{String.trim(term)}%"
    from(b in query, where: ilike(b.name, ^pattern) or ilike(b.description, ^pattern))
  end

  defp filter_by_search_term(query, _), do: query

  # 4 POSTGIS SPATIAL GEOFENCE TRACKER
  # Variant A: Explicit Map Box Coordinates (North, South, East, West)
  defp filter_by_geofence(query, %{"north" => n, "south" => s, "east" => e, "west" => w}) do
    # Build a PostGIS 2D polygon box out of viewport dimensions to execute index intersections
    from(b in query,
      where:
        fragment(
          "st_contains(st_makeenvelope(?, ?, ?, ?, 4326), ?)",
          type(^w, :float),
          type(^s, :float),
          type(^e, :float),
          type(^n, :float),
          b.location
        )
    )
  end

  # Variant B: Center Pin Coordinates (Lat/Lng) + Radius Distance Meters Threshold
  defp filter_by_geofence(query, %{"latitude" => lat, "longitude" => lng, "radius_meters" => rad}) do
    # ST_DWithin performs index-accelerated point checks, projecting geography coordinates cleanly
    from(b in query,
      where:
        fragment(
          "st_dwithin(?.::geography, st_setsrid(st_makepoint(?, ?), 4326)::geography, ?)",
          b.location,
          type(^lng, :float),
          type(^lat, :float),
          type(^rad, :float)
        )
    )
  end

  defp filter_by_geofence(query, _), do: query

  # 5 Sorting Prioritization Order Layer
  defp order_by_metrics(query, %{"sort" => "top_voted"}) do
    from(b in query, order_by: [desc: b.upvotes_count, desc: b.inserted_at])
  end

  defp order_by_metrics(query, _) do
    from(b in query, order_by: [desc: b.inserted_at])
  end
end

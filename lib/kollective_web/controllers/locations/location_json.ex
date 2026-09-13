defmodule KollectiveWeb.LocationJSON do
  @moduledoc """
  Renders global ballot lookups, dynamically handling both single-node
  address configurations and multi-ward local body arrays.
  """

  @doc """
  Main entry point to serialize the office resolution payload.
  """
  def offices(%{payload: payload}) do
    metadata = Map.get(payload, :metadata, %{})

    %{
      status: "success",
      strategy_used: Map.get(payload, :strategy_used, "direct_lookup"),
      metadata: %{
        state: Map.get(metadata, :state),
        county: Map.get(metadata, :county),
        city: Map.get(metadata, :city),
        sub_district: Map.get(metadata, :sub_district),
        area_type: Map.get(metadata, :area_type),
        pincode: Map.get(metadata, :pincode),
        fallback_used: Map.get(metadata, :fallback_used, false),
        resolved_district: Map.get(metadata, :resolved_district),
        message: Map.get(metadata, :message)
      },
      # Dynamically serialize either an explicitly matched list of nodes or an empty array
      local_bodies: render_local_bodies(Map.get(payload, :local_bodies)),
      offices: Enum.map(Map.get(payload, :offices, []), &serialize_office/1)
    }
  end

  def offices(payload) when is_map(payload), do: offices(%{payload: payload})

  @doc """
  Serializes a list of matched cities for autosuggest dropdowns.
  """
  def cities(cities) when is_list(cities) do
    %{data: Enum.map(cities, &city/1)}
  end

  def city(c) do
    %{
      id: c.id,
      name: "#{c.name}, #{c.state}",
      lat: c.latitude,
      lon: c.longitude
    }
  end

  @doc """
  Serializes district suggestion payloads.
  """
  def districts(districts) when is_list(districts) do
    %{data: districts}
  end

  def district(d) do
    %{data: d}
  end

  # --- Private Serialization Mappers ---

  defp render_local_bodies(nil), do: []

  defp render_local_bodies(nodes) when is_list(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        level: node.level,
        name: node.name,
        local_type: node.local_type,
        area_type: node.area_type,
        lgd_code: node.lgd_code
      }
    end)
  end

  defp serialize_office(office) do
    %{
      office_id: office.office_id,
      category: office.category,
      title: office.title,
      scope: office.scope,
      desc: office.desc,
      # 🚀 Exposes "urban" | "rural" | nil directly to React
      area_type: office.area_type,
      term_years: Map.get(office, :term_years),
      qualifications: Map.get(office, :qualifications) || %{},
      run_note: Map.get(office, :run_note)
    }
  end
end

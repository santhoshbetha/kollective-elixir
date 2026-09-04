# priv/repo/seeds_global_geo.exs
alias Kollective.Repo
alias Kollective.Governance.GeoNode

defmodule GlobalGeoSeeder do
  @moduledoc """
  Implements a reusable spatial ingestion utility capable of parsing and seeding
  any administrative depth layer globally, using robust metadata key fallbacks.
  """

  @doc """
  Executes a schema-driven bulk polygon file import pipeline task.

  Parameters:
    - filename: File target name inside priv/repo/data/ (e.g., "indian-districts-simplified.json")
    - (https://gist.github.com/maneetgoyal/c64e9a177a993a8081d8943d0948fa16)
    - country_code: ISO 2-letter country indicator code (e.g., "IN", "US")
    - level: Target destination depth integer (1 = State, 2 = District/County, 3 = City/Block)
    - local_type: Descriptive context type naming tag string (e.g., "District", "Municipality")
    - default_area_type: Fallback string value if metadata column lacks an explicit classification tag
  """
  def run(filename, country_code, level, local_type, default_area_type \\ "urban") do
    cc = String.upcase(country_code)
    geojson_file_path = Path.join([:code.priv_dir(:kollective), "repo", "data", filename])

    unless File.exists?(geojson_file_path) do
      IO.puts(:stderr, "❌ Error: Place your source map file at #{geojson_file_path} first!")
      System.halt(1)
    end

    IO.puts "📂 [Global Geo Seeder] Reading map asset: #{filename}..."
    raw_json_string = File.read!(geojson_file_path)
    %{"features" => features} = Jason.decode!(raw_json_string)

    IO.puts "🚀 Processing and writing #{Enum.count(features)} boundaries into GeoNodes [#{cc} - Level #{level} - #{local_type}]..."

    Repo.transaction(fn ->
      Enum.each(features, fn feature ->
        %{"properties" => properties, "geometry" => geometry} = feature

        # 1. 🌟 COMPACT FALLBACK LOOKUPS FOR STATE & DISTRICT NAMES
        # Automatically catches properties["state"] and properties["district"] from the new file!
        state_name = properties["ST_NM"] || properties["state_name"] || properties["State_Name"] || properties["state"] || properties["State"]
        district_name = properties["DIST_NM"] || properties["district_name"] || properties["District"] || properties["district"] || properties["District_Name"]

        # Determine current node target name dynamically based on depth
        name = if level == 1, do: state_name, else: district_name

        if is_nil(name) or String.trim(name) == "" do
          IO.puts("⚠️ Skipping a feature node: Unable to discover a naming key property in properties: #{inspect(properties)}")
        else
          # 2. 🌟 FALLBACK AREA TYPE EXTRACTOR
          file_area_type = properties["area_type"] || properties["AREA_TYPE"] || properties["type"] || default_area_type
          area_type = if file_area_type, do: String.downcase(to_string(file_area_type)), else: nil

          # 3. Handle Parent Identity Resolution Dynamic Linking
          parent_id = resolve_parent_id(cc, level, state_name)

          # 4. Decode Polygon boundaries data coordinates straight into PostGIS data structs
          postgis_geom = Geo.JSON.decode!(geometry)

          node_params = %{
            country_code: cc,
            level: level,
            name: String.trim(to_string(name)),
            local_type: local_type,
            area_type: area_type,
            parent_id: parent_id,
            geom: postgis_geom
          }

          # Safe Atomic Upsert execution
          %GeoNode{}
          |> GeoNode.changeset(node_params)
          |> Repo.insert!(
            on_conflict: {:replace, [:geom, :parent_id, :local_type, :area_type]},
            conflict_target: [:country_code, :level, :name]
          )
        end
      end)
    end, timeout: :infinity)

    IO.puts "✅ Successfully synchronized boundary schema layouts for [#{local_type}] layers!"
  end

  # Resolves parent IDs automatically to hook up tree branches accurately
  defp resolve_parent_id(_country, 1, _state_name), do: nil # Top tier has no local parents
  defp resolve_parent_id(country, _level, state_name) when is_binary(state_name) do
    cleaned_parent = String.trim(state_name)

    case Repo.get_by(GeoNode, country_code: country, level: 1, name: cleaned_parent) do
      nil ->
        # Auto-create a temporary placeholder parent node if it hasn't been seeded yet
        placeholder = Repo.insert!(%GeoNode{
          country_code: country,
          level: 1,
          name: cleaned_parent,
          local_type: "State"
        })
        placeholder.id
      parent_node ->
        parent_node.id
    end
  end
  defp resolve_parent_id(_country, _level, _nil_state), do: nil
end

# =========================================================================
# TRIGGER PIPELINE EXECUTION BLOCK
# =========================================================================
# Point to your exact newly downloaded filename.
# Default fallback area_type matches "urban", if your dataset breaks a region
# into independent urban/rural files, pass "rural" explicitly as the 5th argument.
GlobalGeoSeeder.run("indian-districts-simplified.json", "IN", 2, "District", "urban") #level = 2

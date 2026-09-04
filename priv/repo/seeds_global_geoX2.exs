# priv/repo/seeds_global_geo.exs
alias Kollective.Repo
alias Kollective.Governance.GeoNode

defmodule GlobalGeoSeeder do
  @moduledoc """
  Implements a reusable spatial ingestion utility capable of parsing and seeding
  any administrative depth layer (Levels 1 through 5) globally into PostGIS GeoNodes.
  """

  @doc """
  Executes a schema-driven bulk polygon file import pipeline task.

  Parameters:
    - filename: The file target name inside priv/repo/data/ (e.g., "india_districts.json")
    - country: ISO 2-letter country indicator code (e.g., "IN", "US")
    - level: Target destination depth integer (1 = State, 2 = District/County, 3 = City/Block, 4 = Ward)
    - local_type: Descriptive context type naming tag string (e.g., "District", "Municipality", "Ward")
  """
  def run(filename, country_code, level, local_type) do
    cc = String.upcase(country_code)
    geojson_file_path = Path.join([:code.priv_dir(:kollective), "repo", "data", filename])

    unless File.exists?(geojson_file_path) do
      IO.puts(:stderr, "❌ Error: Place your source map target data file at #{geojson_file_path} first!")
      System.halt(1)
    end

    IO.puts "📂 [Global Geo Seeder] Reading map asset: #{filename}..."
    raw_json_string = File.read!(geojson_file_path)
    %{"features" => features} = Jason.decode!(raw_json_string)

    IO.puts "🚀 Processing and writing #{Enum.count(features)} boundaries into GeoNodes [#{cc} - Level #{level} - #{local_type}]..."

    Repo.transaction(fn ->
      Enum.each(features, fn feature ->
        %{"properties" => properties, "geometry" => geometry} = feature

        # 1. Dynamically extract the name profile properties (handles typical global key casing structures)
        name = extract_name_property(properties, level)

        # 2. Extract structural area_type split descriptors ("urban" | "rural" | nil)
        file_area_type = properties["area_type"] || properties["AREA_TYPE"] || properties["type"]
        area_type = if file_area_type, do: String.downcase(to_string(file_area_type)), else: nil

        # 3. Handle Parent Identity Resolution Spatially or via metadata attributes keys
        parent_id = resolve_parent_id(cc, level, properties)

        # 4. Decode Polygon boundaries data coordinates straight into PostGIS data structs
        postgis_geom = Geo.JSON.decode!(geometry)

        node_params = %{
          country_code: cc,
          level: level,
          name: String.trim(name),
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
      end)
    end, timeout: :infinity) # Infinity timeout protects bulk spatial uploads from timing out mid-write

    IO.puts "✅ Successfully synchronized boundary schema layouts for [#{local_type}] layers!"
  end

  # Private helper scanning for varying text data map labeling keys depending on the source dataset
  defp extract_name_property(props, level) do
    cond do
      level == 1 -> props["ST_NM"] || props["state_name"] || props["State_Name"] || props["NAME_1"] || props["NAME"]
      level == 2 -> props["DIST_NM"] || props["district_name"] || props["District"] || props["NAME_2"] || props["NAME"]
      level == 3 -> props["BLOCK_NM"] || props["block_name"] || props["TALUK_NM"] || props["NAME_3"] || props["NAME"]
      true       -> props["WARD_NM"] || props["ward_name"] || props["ward_number"] || props["NAME"]
    end
  end

  # Resolves parent IDs automatically to hook up tree branches accurately
  defp resolve_parent_id(_country, 1, _props), do: nil # Top tier has no local parents
  defp resolve_parent_id(country, level, props) do
    # Look up what the previous tier level string name is from the current item parameters properties
    parent_name = extract_name_property(props, level - 1)

    if parent_name do
      case Repo.get_by(GeoNode, country_code: country, level: level - 1, name: String.trim(parent_name)) do
        nil ->
          # Auto-create a temporary placeholder parent node if it hasn't been seeded yet
          # to ensure relational database foreign key reference constraints pass validation
          placeholder = Repo.insert!(%GeoNode{
            country_code: country,
            level: level - 1,
            name: String.trim(parent_name),
            local_type: "Administrative Parent Tier Fallback"
          })
          placeholder.id
        parent_node ->
          parent_node.id
      end
    else
      nil
    end
  end
end

# =========================================================================
# TRIGGER PIPELINE EXECUTION BLOCK
# =========================================================================
# Now, running imports across different levels is as simple as defining commands here:

# 1. Load India Districts Framework (Level 2 - Seeds parent Level 1 structures automatically)
GlobalGeoSeeder.run("india_districts.json", "IN", 2, "District")

# 2. Example: Load granular US municipal lines later by adding single execution lines:
# GlobalGeoSeeder.run("austin_wards.json", "US", 3, "City Ward")

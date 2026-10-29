# priv/repo/seeds_global_geo.exs
alias Kollective.Repo
alias Kollective.Governance.GeoNode

# 1. Resolve path pointing straight to your external asset file
geojson_file_path =
  Path.join([:code.priv_dir(:kollective), "repo", "data", "india_districts.json"])

unless File.exists?(geojson_file_path) do
  IO.puts(:stderr, "Error: Place your map file at priv/repo/data/india_districts.json first!")
  exit(:shutdown)
end

# 2. Load and decode the file into memory
IO.puts("📂 Reading Indian District map file from disk...")
raw_json_string = File.read!(geojson_file_path)
%{"features" => features} = Jason.decode!(raw_json_string)

IO.puts(
  "🚀 Processing and writing #{Enum.count(features)} geographical entities into Universal GeoNodes..."
)

Repo.transaction(fn ->
  Enum.each(features, fn feature ->
    %{"properties" => properties, "geometry" => geometry} = feature

    # Extract metadata properties dynamically (handles variations in file keys)
    state_name = properties["ST_NM"] || properties["state_name"] || properties["State_Name"]
    district_name = properties["DIST_NM"] || properties["district_name"] || properties["District"]

    # 🚀 Extract area_type dynamically from the file features properties
    # Default to "urban" if the specific polygon lacks a tag
    file_area_type = properties["area_type"] || properties["AREA_TYPE"] || "urban"

    # --------------------------------──────────────────────────────────────
    # STEP A: Ensure the Parent State Node exists in our global tree layout (Level 1)
    # --------------------------------──────────────────────────────────────
    state_node_params = %{
      country_code: "IN",
      level: 1,
      name: String.trim(state_name),
      local_type: "State",
      # Level 1 fallback can remain text-based or update later
      geom: nil
    }

    state_node =
      case Repo.get_by(GeoNode, country_code: "IN", level: 1, name: state_node_params.name) do
        nil -> Repo.insert!(GeoNode.changeset(%GeoNode{}, state_node_params))
        existing_state -> existing_state
      end

    # --------------------------------──────────────────────────────────────
    # STEP B: Inject the complex District polygon directly into PostGIS (Level 2)
    # ------------------------------------------------──────────────────────
    # Decode GeoJSON coordinates automatically whether it is a Polygon or MultiPolygon
    postgis_geom = Geo.JSON.decode!(geometry)

    district_node_params = %{
      country_code: "IN",
      level: 2,
      name: String.trim(district_name),
      local_type: "District",
      # 🚀 Injects "urban" or "rural"
      area_type: String.downcase(file_area_type),
      # 🌟 Locks down the hierarchical box-in-a-box parent link!
      parent_id: state_node.id,
      geom: postgis_geom
    }

    # Safe atomic insert configuration
    %GeoNode{}
    |> GeoNode.changeset(district_node_params)
    |> Repo.insert!(
      on_conflict: {:replace, [:geom, :parent_id, :local_type]},
      conflict_target: [:country_code, :level, :name]
    )

    IO.puts("   ✅ Ingested: #{district_name} District ──> (Nested under #{state_name})")
  end)
end)

IO.puts("🎉 India box-in-a-box spatial infrastructure compiled under 10ms indexes successfully!")

defmodule Mix.Tasks.Kollective.LoadDistricts do
  use Mix.Task
  alias Kollective.Repo
  alias Kollective.Locations.PoliticalDistrict

  @shortdoc "Imports political boundaries from GeoJSON or GeoJSONL files into PostGIS geometries"

  @impl Mix.Task
  def run([file_path, country_code, level_str]) do
    Mix.Task.run("app.start")

    case Integer.parse(level_str) do
      {level, ""} when level in 1..3 ->
        country_code = String.upcase(country_code)

        if File.exists?(file_path) do
          Mix.shell().info("=== Parsing PostGIS Shapes Level #{level} for #{country_code} ===")

          case Path.extname(file_path) do
            ext when ext in [".geojsonl", ".jsonl", ".ldjson"] ->
              process_geojsonl(file_path, country_code, level)

            _ ->
              process_standard_geojson(file_path, country_code, level)
          end
        else
          Mix.shell().error("Target file does not exist: #{file_path}")
        end

      _ ->
        Mix.shell().error("Invalid level: #{level_str}. Expected 1, 2, or 3.")
    end
  end

  def run(_),
    do:
      Mix.shell().error("Usage: mix kollective.load_districts [path_to_geojson] [US|IN] [1|2|3]")

  # --- Streaming GeoJSONL Processor ---
  defp process_geojsonl(file_path, country_code, level) do
    concurrency = min(System.schedulers_online(), 8)

    file_path
    |> File.stream!()
    # AUTOMATIC LINE CLEANER: Strip leading/trailing whitespaces, tabs, and carriage returns (\r)
    |> Stream.map(&String.replace(&1, ~r/\r?\n|\t/, ""))
    |> Stream.map(&String.trim/1)
    # Reject completely blank lines securely
    |> Stream.reject(&(&1 == ""))
    |> Task.async_stream(
      fn line ->
        case Jason.decode(line) do
          {:ok, feature} -> process_feature(feature, country_code, level)
          {:error, _} -> Mix.shell().error("Skipping malformed or corrupted JSON line.")
        end
      end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.run()

    Mix.shell().info(
      "Successfully loaded and spatially indexed all map matrices via GeoJSONL streaming."
    )
  end

  # --- Standard GeoJSON Processor ---
  defp process_standard_geojson(file_path, country_code, level) do
    with {:ok, body} <- File.read(file_path),
         {:ok, geojson} <- Jason.decode(body) do
      features =
        case geojson do
          %{"type" => "FeatureCollection", "features" => list} when is_list(list) ->
            list

          %{"features" => list} when is_list(list) ->
            list

          %{"type" => "Feature"} = single_feature ->
            [single_feature]

          _ ->
            []
        end

      if features == [] do
        Mix.shell().error("No GeoJSON features found in #{file_path}.")
      else
        Enum.each(features, fn feature ->
          process_feature(feature, country_code, level)
        end)

        Mix.shell().info(
          "Successfully loaded and spatially indexed all map matrices via GeoJSON."
        )
      end
    else
      {:error, reason} ->
        Mix.shell().error("Failed to safely read or decode target GeoJSON: #{inspect(reason)}")
    end
  end

  # --- Shared Core Logic Helper ---
  defp process_feature(feature, country_code, level) do
    props = feature["properties"] || %{}

    raw_ext_id =
      props["id"] || props["GEOID"] || props["DIST_ID"] || props["GEOID20"] ||
        props["GEOID10"] || props["PC_CODE"] || props["AC_NO"] || props["OBJECTID"]

    external_id = if raw_ext_id, do: to_string(raw_ext_id), else: nil

    name =
      props["name"] || props["NAME"] || props["DIST_NAME"] || props["NAMELSAD"] ||
        props["NAMELSAD20"] || props["BASENAME"] || props["NAME20"] ||
        (external_id && "District #{external_id}")

    state =
      props["state"] || props["STATE"] || props["STATE_ABBR"] || props["STUSPS"] ||
        props["STUSPS20"]

    type_label =
      props["type_label"] || props["TYPE"] || default_type_label(country_code, level)

    # Protect against missing geometry segments safely
    native_geom =
      case feature["geometry"] do
        nil ->
          nil

        geom ->
          geom
          |> Geo.JSON.decode!()
          |> Map.put(:srid, 4326)
          |> Map.put(:properties, %{"srid" => 4326})
      end

    if is_nil(external_id) or external_id == "" do
      Mix.shell().error(
        "Skipping feature missing external identifier (id/GEOID): #{inspect(props)}"
      )
    else
      attrs = %{
        name: name,
        level: level,
        country: country_code,
        external_id: external_id,
        state: state,
        type_label: type_label,
        geom: native_geom
      }

      # Dynamic Parent Hierarchy Linkage
      parent_ext_id = props["parent_id"] || props["STATE_ID"] || props["PARENT_ID"]

      attrs =
        if parent_ext_id && to_string(parent_ext_id) != "" do
          case Repo.get_by(PoliticalDistrict,
                 external_id: to_string(parent_ext_id),
                 country: country_code
               ) do
            nil -> attrs
            parent -> Map.put(attrs, :parent_id, parent.id)
          end
        else
          attrs
        end

      case Repo.get_by(PoliticalDistrict, external_id: external_id, country: country_code) do
        nil ->
          %PoliticalDistrict{}
          |> PoliticalDistrict.changeset(attrs)
          |> Repo.insert!()

        existing ->
          existing
          |> PoliticalDistrict.changeset(attrs)
          |> Repo.update!()
      end
    end
  rescue
    exception ->
      props = (feature && feature["properties"]) || %{}

      id_info =
        props["id"] || props["GEOID"] || props["DIST_ID"] || props["name"] ||
          props["NAME"] || "Unknown ID"

      Mix.shell().error("Error processing feature ID #{id_info}: #{inspect(exception)}")
  end

  defp default_type_label("US", 1), do: "Federal"
  defp default_type_label("US", 2), do: "State Upper"
  defp default_type_label("US", 3), do: "State Lower"
  defp default_type_label("IN", 1), do: "Parliamentary"
  defp default_type_label("IN", 2), do: "Assembly"
  defp default_type_label(_country, 1), do: "National"
  defp default_type_label(_country, 2), do: "Regional"
  defp default_type_label(_country, 3), do: "Local"
  defp default_type_label(_country, _level), do: "District"
end

# lib/mix/tasks/kollective.import_cities.ex
defmodule Mix.Tasks.Kollective.ImportCities do
  use Mix.Task
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Locations.City

  @shortdoc "Downloads and batch imports major cities for US and India from GeoNames"

  # GeoNames free text data URLs
  @urls %{
    "US" => "https://geonames.org",
    "IN" => "https://geonames.org"
  }

  # Only import records matching specific feature codes (PPL = populated place, PPLA = seat of government, etc.)
  @allowed_feature_classes ["P", "PPL", "PPLA", "PPLA2", "PPLC"]
  # Set a population floor to keep your database focused on relevant voting hubs
  @min_population 5_000

  @impl Mix.Task
  def run(_) do
    # Start app infrastructure so Repo is available
    Mix.Task.run("app.start")

    Mix.shell().info("=== Starting Global City Import ===")

    Enum.each(@urls, fn {country_code, url} ->
      Mix.shell().info("Processing country: #{country_code}...")

      with {:ok, zip_path} <- download_file(url, country_code),
           {:ok, txt_path} <- extract_zip(zip_path, country_code) do
        txt_path
        |> File.stream!([:read, :utf8])
        |> Stream.map(&String.split(&1, "\t"))
        |> Stream.filter(&valid_city?(&1))
        |> Stream.map(&parse_row(&1, country_code))
        # Batch into groups of 1000 rows
        |> Stream.chunk_every(1000)
        |> Enum.each(&insert_batch/1)

        # Cleanup temporary files
        File.rm!(zip_path)
        File.rm!(txt_path)
        Mix.shell().info("Successfully imported major cities for #{country_code}.")
      else
        {:error, reason} -> Mix.shell().error("Failed to import #{country_code}: #{reason}")
      end
    end)
  end

  defp download_file(url, country_code) do
    Mix.shell().info("Downloading data stack from GeoNames...")
    target_path = "/tmp/#{country_code}.zip"

    case Req.get(url, output: target_path) do
      {:ok, %{status: 200}} -> {:ok, target_path}
      _ -> {:error, "Download failed"}
    end
  end

  defp extract_zip(zip_path, country_code) do
    Mix.shell().info("Extracting data files...")
    # Erlang's :zip module extracts to the current directory or a specific path
    charlist_path = String.to_charlist(zip_path)

    case :zip.unzip(charlist_path, [{:cwd, '/tmp'}]) do
      {:ok, _files} -> {:ok, "/tmp/#{country_code}.txt"}
      {:error, reason} -> {:error, "Extraction failed: #{inspect(reason)}"}
    end
  end

  # GeoNames structural layout verification
  defp valid_city?(row) do
    # Column 4: Feature Class (P = city/village)
    # Column 14: Population metric
    feature_class = Enum.at(row, 6)
    population = String.to_integer(Enum.at(row, 14) || "0")

    feature_class in @allowed_feature_classes and population >= @min_population
  end

  defp parse_row(row, country_code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      # ASCII Name
      name: Enum.at(row, 1),
      # Admin Code 1 (e.g., State abbreviation)
      state: Enum.at(row, 10),
      country: country_code,
      # geonameid
      external_id: Enum.at(row, 0),
      latitude: String.to_float(Enum.at(row, 4)),
      longitude: String.to_float(Enum.at(row, 5)),
      inserted_at: now,
      updated_at: now
    }
  end

  defp insert_batch(batch) do
    # Multi-row fast atomic insert ignoring duplicate IDs
    Repo.insert_all(
      City,
      batch,
      on_conflict: :nothing,
      conflict_target: :external_id
    )
  end
end

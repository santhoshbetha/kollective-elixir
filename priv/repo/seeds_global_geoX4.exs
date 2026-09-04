# priv/repo/seeds_global_geo.exs
alias Kollective.Repo
alias Kollective.Governance.GeoNode

defmodule LgdBulkImporter do
  @moduledoc """
  Streams large LGD master CSV spreadsheets into the unified universal GeoNode tree.
  """

  def import_from_csv(filename) do
    csv_path = Path.join([:code.priv_dir(:kollective), "repo", "data", filename])

    unless File.exists?(csv_path) do
      IO.puts(:stderr, "❌ Missing data target file. Place master CSV at: priv/repo/data/#{filename}")
      System.halt(1)
    end

    IO.puts "Streaming LGD CSV directory arrays smoothly into background pipeline..."

    csv_path
    |> File.stream!()
    |> NimbleCSV.RFC4180.parse_stream()
    # Process records in batches of 500 to keep memory low
    |> Stream.chunk_every(500) # Keep server memory footprint exceptionally bounded
    |> Enum.each(fn batch ->
         Repo.transaction(fn ->
           Enum.each(batch, fn [state_name, state_code, dist_name, dist_code, block_name, block_code, body_name, body_code, body_type] ->

             # Step 1: Ensure Level 1 State Node Exists
             state = upsert_node("IN", 1, state_name, "State", nil, state_code, nil)

             # Step 2: Ensure Level 2 District Node Exists
             district = upsert_node("IN", 2, dist_name, "District", nil, dist_code, state.id)

             # Step 3: Handle Blocks / Sub-Districts if Rural (Nullable for urban local bodies)
             parent_id_for_body =
               if String.trim(block_name) != "" and body_type == "gram_panchayat" do
                 block = upsert_node("IN", 3, block_name, "Block", "rural", block_code, district.id)
                 block.id
               else
                 district.id
               end

             # Step 4: Map the hyper-local Local Body (Gram Panchayat / Municipal Council)
             area_classification = if body_type == "gram_panchayat", do: "rural", else: "urban"
             local_type_label = if area_classification == "rural", do: "Gram Panchayat", else: "Urban Local Body"

             upsert_node("IN", 4, body_name, local_type_label, area_classification, body_code, parent_id_for_body)
           end)
         end, timeout: :infinity)
         IO.write(".")
       end)

     IO.puts "\n✅ LGD Master relational hierarchy structural arrays ingested successfully!"
  end

  defp upsert_node(country, level, name, local_type, area_type, code_str, parent_id) do
    code = String.to_integer(String.trim(code_str))
    cleaned_name = String.trim(name)

    # High-performance INSERT ON CONFLICT simulation lookup pattern
    case Repo.get_by(GeoNode, country_code: country, level: level, lgd_code: code) do
      nil ->
        %GeoNode{}
        |> GeoNode.changeset(%{
             country_code: country,
             level: level,
             name: cleaned_name,
             local_type: local_type,
             area_type: area_type,
             lgd_code: code,
             parent_id: parent_id
           })
        |> Repo.insert!()
      existing_node ->
        existing_node
    end
  end
end

# Trigger execution over the standard file
LgdBulkImporter.import_from_csv("lgd_master.csv")

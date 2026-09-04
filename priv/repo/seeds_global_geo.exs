# priv/repo/seeds_global_geo.exs
alias Kollective.Repo
alias Kollective.Governance.GeoNode

defmodule IndiaLgdBulkImporter do
  @moduledoc """
  Ingests separate PRI (Rural) and ULB (Urban) CSV datasets into the global tree.
  """

  def run do
    rural_csv = Path.join([:code.priv_dir(:kollective), "repo", "data", "pri_local_bodies.csv"])
    urban_csv = Path.join([:code.priv_dir(:kollective), "repo", "data", "urban_local_bodies.csv"])

    # --- PASS 1: STREAM RURAL DATA (PRI) ---
    if File.exists?(rural_csv) do
      IO.puts "=== PASS 1: Streaming Rural PRI Local Bodies ==="
      rural_csv
      |> File.stream!()
      |> NimbleCSV.RFC4180.parse_stream()
      |> Stream.chunk_every(500)
      |> Enum.each(fn batch ->
           Repo.transaction(fn ->
             Enum.each(batch, fn [_sno, type_code, type_name, lb_code, _lb_ver, lb_name_en, _lb_local, parent_code, state_code, _state_name] ->
               state_lgd = String.to_integer(state_code)
               body_lgd = String.to_integer(lb_code)

               # Map to universal level layers based on PRI governance definitions
               level = case type_name do
                 "Zilla Parishad" -> 2
                 "Panchayat Samiti" -> 3
                 "Gram Panchayat" -> 4
                 _ -> 4
               end

               # Ingest into universal tree table
               upsert_node(
                 level,
                 lb_name_en,
                 "rural",
                 body_lgd,
                 String.to_integer(parent_code),
                 state_lgd
                )
             end)
           end)
         end)
    end

    # --- PASS 2: STREAM URBAN DATA (ULB) ---
    if File.exists?(urban_csv) do
      IO.puts "=== PASS 2: Streaming Urban ULB Local Bodies ==="
      urban_csv
      |> File.stream!()
      |> NimbleCSV.RFC4180.parse_stream()
      |> Stream.chunk_every(500)
      |> Enum.each(fn batch ->
           Repo.transaction(fn ->
             Enum.each(batch, fn [_sno, state_code, _state_name, lb_code, _lb_ver, lb_name_en, _lb_local, type_code, _c_code] ->
               # Urban units hook up straight to District parents as Level 4 nodes
               upsert_node(
                4,
                lb_name_en,
                "urban",
                String.to_integer(lb_code),
                nil,
                String.to_integer(state_code)
              )
             end)
           end)
         end)
    end
  end

  # Update inside your priv/repo/seeds_global_geo.exs file
  defp upsert_node(level, name, area_type, lgd_code, parent_lgd, state_lgd, state_name_from_row) do

    # 1. Ensure the Level 1 State is seeded first using the text inside the current CSV row
    state_node = case Repo.get_by(GeoNode, country_code: "IN", level: 1, lgd_code: state_lgd) do
      nil ->
        Repo.insert!(%GeoNode{
          country_code: "IN",
          level: 1,
          name: String.trim(state_name_from_row), # e.g., "Karnataka"
          local_type: "State",
          lgd_code: state_lgd
        })
      existing_state ->
        # If it exists but has a placeholder name, update it with the clean string name
        if String.contains?(existing_state.name, "State Code") do
          existing_state
          |> GeoNode.changeset(%{name: String.trim(state_name_from_row)})
          |> Repo.all()
        else
          existing_state
        end
    end

    # 2. Resolve the immediate parent_id for the current node hierarchy layer
    parent_id = case level do
      2 -> state_node.id # Zilla Parishads link straight to the State ID
      _ -> resolve_parent_id(level, parent_lgd)
    end

    # 3. Insert the target node safely
    case Repo.get_by(GeoNode, country_code: "IN", level: level, lgd_code: lgd_code) do
      nil ->
        %GeoNode{
          country_code: "IN",
          level: level,
          name: String.trim(name),
          local_type: "LGD_Node",
          area_type: area_type,
          lgd_code: lgd_code,
          parent_id: parent_id
        } |> Repo.insert!()
      existing -> existing
    end
  end

  defp resolve_parent_id(2, _parent_lgd, state_lgd) do
    # It looks up the parent State (Level 1) using the state_lgd code
    case Repo.get_by(GeoNode, country_code: "IN", level: 1, lgd_code: state_lgd) do
      nil ->
        # 🚀 THE AUTO-HEALING SAFETY NET:
        # If the State doesn't exist yet, we can update our logic to create it on the fly!
        new_state = Repo.insert!(%GeoNode{
          country_code: "IN",
          level: 1,
          name: "State Code #{state_lgd}", # Placeholder that gets updated, or parsed from the row
          local_type: "State",
          lgd_code: state_lgd
        })
        new_state.id

      state -> state.id
    end
  end

  defp resolve_parent_id(level, parent_lgd, _state_gld) do
    if parent_lgd do
      case Repo.get_by(GeoNode, country_code: "IN", level: level - 1, lgd_code: parent_lgd) do
        nil -> nil
        parent -> parent.id
      end
    else
      nil
    end
  end
end

IndiaLgdBulkImporter.run()

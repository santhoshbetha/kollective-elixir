# priv/repo/seeds_lgd_pincodes.exs
import Ecto.Query
alias Kollective.Repo
alias Kollective.Governance.{GeoNode, PincodeMapping}

defmodule IndiaPincodeSeeder do
  def run do
    csv_path = Path.join([:code.priv_dir(:kollective), "repo", "data", "pincode_directory.csv"])

    unless File.exists?(csv_path) do
      IO.puts(:stderr, "❌ Missing postal mapping file at priv/repo/data/pincode_directory.csv")
      System.halt(1)
    end

    IO.puts "Streaming postal matrix lines into data injection pipeline..."

    csv_path
    |> File.stream!()
    |> NimbleCSV.RFC4180.parse_stream()
    |> Stream.chunk_every(200)
    |> Enum.each(fn batch ->
         Repo.transaction(fn ->
           Enum.each(batch, fn [_office, pincode, _type, _status, _div, _reg, _circ, taluk, district, _state] ->
             clean_pincode = String.trim(pincode)
             clean_district = String.trim(district)
             clean_block = String.trim(taluk)

             # 🌟 Use text intersection matching to bind the postal map to the LGD tree
             query =
               from lb in GeoNode,
                 join: d in GeoNode, on: lb.parent_id == d.id,
                 where: lb.level == 4 and ilike(d.name, ^clean_district) and
                        (ilike(lb.name, ^"%#{clean_block}%") or ilike(lb.name, ^"%#{clean_block}%")),
                 select: lb.id,
                 limit: 1

             case Repo.one(query) do
               nil -> :skip
               geo_node_id ->
                 %PincodeMapping{pincode: clean_pincode, geo_node_id: geo_node_id}
                 |> Repo.insert(on_conflict: :nothing, conflict_target: [:pincode, :geo_node_id])
             end
           end)
         end, timeout: 60_000)
       end)

     IO.puts "🎉 PIN code cross-reference sync complete!"
  end
end

IndiaPincodeSeeder.run()

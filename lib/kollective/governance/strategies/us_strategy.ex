defmodule Kollective.Governance.Strategies.USStrategy do
  @behaviour Kollective.Governance.LocationStrategy

  @base_url "https://www.googleapis.com/civicinfo/v2/divisionsByAddress"

  @impl true
  def fetch_context(address) do
    api_key = Application.get_env(:your_app, :google_civic_api_key)

    # Hits the target Google endpoint to receive raw boundary tokens efficiently
    case Req.get(@base_url, query: %{"address" => address, "key" => api_key}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_ocd_divisions(body)}

      {:ok, %{status: status}} ->
        {:error, "Google Civic returned an unhandled HTTP status code: #{status}"}

      {:error, _reason} ->
        {:error, "Failed to connect to United States civic division mapping providers."}
    end
  end

  # Google does the heavy geographic intersection lifted work,
  # we simply clean the resulting string tokens into our global keys!
  # 🌟 Integrates the exact OCD-ID mapping logic from the chat doc
  # but formats the output keys into standard, global terminology variables
  defp parse_ocd_divisions(%{"divisions" => divisions, "normalizedInput" => input}) do
    parsed_ocd =
      Enum.reduce(divisions, %{}, fn {ocd_id, data}, acc ->
        name = data["name"]

        cond do
          # Maps US School Districts -> Universal sub_district column
          String.contains?(ocd_id, "/school_district:") -> Map.put(acc, :sub_district, name)
          # Maps US City/Townships -> Universal city column
          String.contains?(ocd_id, "/place:") -> Map.put(acc, :city, name)
          String.contains?(ocd_id, "/parish:") -> Map.put(acc, :parish, name)
          # Maps US Counties -> Universal county column
          String.contains?(ocd_id, "/county:") -> Map.put(acc, :county, name)
          # 🌟 SPECIAL US OVERLAY TARGETS:
          # Instead of managing massive GeoJSON lines, we can dynamically save the parsed district
          # names right into our county or city slots so our universal rules matrix query catches them!
          # e.g., "Texas's 10th Congressional District"
          String.contains?(ocd_id, "/cd:") -> Map.put(acc, :cd, name)
          # State Legislative District Upper
          String.contains?(ocd_id, "/sldu:") -> Map.put(acc, :sldu, name)
          # State Legislative District Lower
          String.contains?(ocd_id, "/sldl:") -> Map.put(acc, :sldl, name)
          true -> acc
        end
      end)

    %{
      # e.g. "TX"
      state: input["state"],
      # e.g. "Travis County"
      county: parsed_ocd[:county],
      city: input["city"] || parsed_ocd[:city],
      # Consolidate overlapping target district scopes into a single text identifier layer
      # so it matches our universal text query database matrix filters flawlessly
      sub_district:
        parsed_ocd[:sub_district] || parsed_ocd[:cd] || parsed_ocd[:sldu] || parsed_ocd[:sldl]
    }
  end

  # Fallback rule intercept if the input address doesn't cross-match any Google divisions
  defp parse_ocd_divisions(_empty_payload) do
    %{state: "Unknown", county: nil, city: nil, sub_district: nil}
  end
end

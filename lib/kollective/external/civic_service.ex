# The Civic Service (Integration)
# We'll use Req to fetch data from the Google Civic API. It translates a street address into the
# specific OCD IDs which contain the district numbers.
defmodule Kollective.External.CivicService do
  @api_key Application.compile_env(:kollective, :google_civic_api_key)
  @base_url "https://googleapis.com"

  def find_districts_by_address(address) do
    params = [
      address: address,
      key: @api_key,
      levels: "country",
      levels: "administrativeArea1",
      levels: "administrativeArea2"
    ]

    case Req.get(@base_url, params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_civic_data(body)}

      {:ok, %{status: 400}} ->
        {:error, "Invalid address format"}

      _ ->
        {:error, "Service unavailable"}
    end
  end

  defp parse_civic_data(body) do
    # Logic to extract district numbers from the 'offices' and 'divisions' keys
    # Example logic for Federal Congress:
    divisions = Map.keys(body["divisions"] || %{})

    %{
      state: extract_state(divisions),
      federal_district: extract_district(divisions, ~r/cd:(\d+)/),
      state_senate_district: extract_district(divisions, ~r/sldu:(\d+)/),
      state_district: extract_district(divisions, ~r/sldl:(\d+)/)
    }
  end

  defp extract_state(divisions) do
    Enum.find_value(divisions, fn d ->
      if String.contains?(d, "state:"), do: String.slice(d, -2..-1) |> String.upcase()
    end)
  end

  defp extract_district(divisions, regex) do
    Enum.find_value(divisions, fn d ->
      case Regex.run(regex, d) do
        [_, num] -> num
        _ -> nil
      end
    end)
  end
end

# Simple client to fetch geocoding data.
# Pass street, city, and state to Geoapify to get a "normalized" address and coordinates.
defmodule Kollective.External.GeoapifyService do
  @api_key Application.compile_env(:kollective, :geoapify_api_key)
  @base_url "https://api.geoapify.com"

  def geocode(street, state, country) do
    params = [
      text: "#{street}, #{state}, #{country}",
      apiKey: @api_key,
      limit: 1
    ]

    case Req.get(@base_url, params: params) do
      {:ok, %{status: 200, body: %{"features" => [first | _]}}} ->
        # Extract normalized address and coordinates
        properties = first["properties"]

        {:ok,
         %{
           lat: properties["lat"],
           lon: properties["lon"],
           formatted: properties["formatted"]
         }}

      _ ->
        {:error, :not_found}
    end
  end
end

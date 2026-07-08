# lib/kollective/workers/geocode_worker.ex
defmodule Kollective.Workers.GeocodeWorker do
  @moduledoc """
  Unified Asynchronous Geographic Encoding Worker.
  Safely resolves text addresses down to PostGIS coordinates via external APIs
  for both Event and Business data models seamlessly.
  """
  use Oban.Worker, queue: :media, max_attempts: 4

  import Ecto.Query
  alias Kollective.Repo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "target_id" => target_id,
          "schema_type" => schema_type,
          "address_text" => address_text
        }
      }) do
    # 1. POLYMORPHIC DETECTOR: Maps string arguments directly to local schema files
    schema_module =
      case schema_type do
        "Business" -> Kollective.Businesses.Business
        "Event" -> Kollective.Events.Event
        _invalid -> raise "Unsupported geocoding target model structural contract."
      end

    # 2. URL-encode the text address string cleanly
    encoded_query = URI.encode_query(%{"q" => address_text, "format" => "json", "limit" => 1})
    url = "https://nominatim.openstreetmap.org/search?#{encoded_query}"

    # 3. Fire the outbound network call with strict timeout limits
    case Req.get(url,
           headers: [{"user-agent", "KollectiveApp/1.0"}],
           receive_timeout: 5000,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: [%{"lat" => lat_str, "lon" => lng_str} | _]}} ->
        lat = String.to_float(lat_str)
        lng = String.to_float(lng_str)
        geo_point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

        # 4. ATOMIC DATABASE WRITE: Writes the PostGIS POINT directly to the target table
        from(x in schema_module, where: x.id == ^target_id)
        |> Repo.update_all(set: [location: geo_point])

        # 5. Broadcast real-time update alerts to refresh active frontend viewports
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:geo_resolution_complete, %{id: target_id, type: schema_type}}
        )

        :ok

      {:ok, %Req.Response{status: 429}} ->
        # Rate limited: Return an error tuple to force Oban to back off and try again later
        {:error, :rate_limited}

      {:ok, %Req.Response{body: []}} ->
        # Address was completely unresolvable: Stop trying so we don't waste worker cycles
        Logger.warning(
          "GEOCODE_NOT_FOUND: Text address '#{address_text}' for #{schema_type} could not be matched."
        )

        :ok

      {:error, reason} ->
        # Network timeout or connection drop: Retry automatically via Oban
        {:error, reason}
    end
  end
end

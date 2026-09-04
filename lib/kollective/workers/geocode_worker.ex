# lib/kollective/workers/geocode_worker.ex
defmodule Kollective.Workers.GeocodeWorker do
  @moduledoc """
  High-Performance Polymorphic Geographic Encoding Worker.
  Safely resolves raw text address properties down to PostGIS POINT geometries
  for both Event and Business standalone schemas asynchronously out-of-band.
  """
  use Oban.Worker, queue: :media, max_attempts: 4

  import Ecto.Query
  alias Kollective.Repo
  require Logger

  # COMPLIANCE ANCHOR: Put your domain contact email here to satisfy Nominatim Usage Policies
  @user_agent "KollectiveApp/1.0 (contact@kollectiveapp.xyz)"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "target_id" => target_id,
          "schema_type" => schema_type,
          "address_text" => address_text
        }
      }) do
    # 1. POLYMORPHIC DETECTOR: Maps incoming strings to clean core schema modules
    schema_module =
      case schema_type do
        "Business" -> Kollective.Businesses.Business
        "Event" -> Kollective.Events.Event
        _invalid -> raise "Unsupported geocoding target model structural contract."
      end

    # 2. URL-encode parameters matching standard open-source API dictionaries
    encoded_query = URI.encode_query(%{"q" => address_text, "format" => "json", "limit" => 1})
    url = "https://openstreetmap.org/search?#{encoded_query}"

    # 3. Fire the outbound network call with strict timeout limits and compliant user-agent headers
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 5000,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: [%{"lat" => lat_str, "lon" => lng_str} | _]}} ->
        lat = String.to_float(lat_str)
        lng = String.to_float(lng_str)
        geo_point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        # 4. ATOMIC DATABASE WRITE WITH TIMESTAMP PROTECTION
        # FIXED: Explicitly append updated_at to ensure caches invalidate cleanly
        from(x in schema_module, where: x.id == ^target_id)
        |> Repo.update_all(set: [location: geo_point, updated_at: now])

        # 5. TARGETED REAL-TIME WEBSOCKET ROUTING PASS
        # FIXED: Direct signals straight to specific resource rooms to refresh active UIs smoothly
        broadcast_geo_resolution(schema_type, target_id, lat, lng)

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

      other ->
        Logger.warning("GEOCODE_UNEXPECTED_RESPONSE: #{inspect(other)}")
        :ok
    end
  end

  # ─── PRIVATE ROUTING DISPATCH MATRIX ───
  defp broadcast_geo_resolution("Event", event_id, lat, lng) do
    # Target the specific event room so active organizers and participants see updates instantly
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{event_id}",
      {"geo_resolution_complete", %{lat: lat, lng: lng}}
    )
  end

  defp broadcast_geo_resolution("Business", business_id, lat, lng) do
    # Target the public signal bus channel to trigger local discovery feed recalibrations
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "feed:public",
      {:business_geo_ready, %{id: business_id, lat: lat, lng: lng}}
    )
  end
end

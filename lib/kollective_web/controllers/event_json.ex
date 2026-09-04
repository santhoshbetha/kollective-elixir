# lib/kollective_web/controllers/event_json.ex
defmodule KollectiveWeb.EventJSON do
  alias KollectiveWeb.PoliticalDistrictJSON

  def index(%{events: events}) do
    %{data: for(event <- events, do: data(event))}
  end

  def show(%{event: event}) do
    %{data: data(event)}
  end

  def data(event) do
    %{
      id: event.id,
      title: event.title,
      description: event.description,
      start_time: event.start_time,
      end_time: event.end_time,
      timezone: event.timezone,
      status: event.event_status,

      # Visuals
      banner_url:
        event.banner_url || Kollective.Events.EventHelpers.get_banner_url(event) ||
          default_banner(),
      logo_url: event.logo_url,

      # Engagement
      participants_count: event.participants_count,
      comments_count: event.comments_count,

      # Geography (Preloaded)
      location: %{
        name: event.location_name,
        city: city_name(event.origin_city),
        address: event.street,
        state: event.origin_state,
        country: event.origin_country,
        # Recursive District Stack (National > State > Local)
        district_l1: PoliticalDistrictJSON.data(event.origin_district_l1),
        district_l2: PoliticalDistrictJSON.data(event.origin_district_l2),
        district_l3: PoliticalDistrictJSON.data(event.origin_district_l3)
      },

      # Author/Candidate Info
      organizer: %{
        id: event.user.id,
        username: event.user.username,
        is_verified: event.user.is_verified
      },
      inserted_at: event.inserted_at
    }
  end

  # Helper: Handles the case where the association is fully preloaded and loaded
  defp city_name(%Kollective.Locations.City{} = city), do: city.name

  # Helper: Fallback if no city is assigned (null) or if it wasn't preloaded
  defp city_name(_), do: nil

  defp default_banner, do: "https://media.kollective.app"

  @doc """
  Serializes a single pending participation request row from the database.
  """
  def participation_request(%{request: request, for: reading_user}) do
    %{
      id: to_string(request.id),

      # 1. Nest the requester's user profile using your optimized AccountJSON
      account: KollectiveWeb.AccountJSON.show(%{user: request.user, for: reading_user}),
      type: "participation_request",
      # Maps directly to your local status strings ("pending", "accepted")
      state: request.status || "pending",

      # Standard international ISO timestamp format string
      created_at: Calendar.strftime(request.inserted_at, "%Y-%m-%dT%H:%M:%SZ")
    }
  end

  @doc """
  Serializes a list of pending attendance request records for the administrator panel grid.
  """
  def participation_requests(%{requests: requests} = opts) do
    # Standard Elixir collection mapping pass instead of an expensive, nested macro loop
    Enum.map(requests, fn request ->
      participation_request(Map.put(opts, :request, request))
    end)
  end
end

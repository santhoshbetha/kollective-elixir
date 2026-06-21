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
      name: event.name,
      description: event.description,
      start_time: event.start_time,
      end_time: event.end_time,
      timezone: event.timezone,

      status: event.event_status,

      # Visuals
      banner_url: event.banner_url || default_banner(),
      logo_url: event.logo_url,

      # Engagement
      participants_count: event.participants_count,
      comments_count: event.comments_count,

      # Geography (Preloaded)
      location: %{
        name: event.location_name,
        city: event.origin_city.name,
        address: event.street,
        state: event.origin_state,
        country: event.origin_country,
        # Recursive District Stack (National > State > Local)
        district_hierarchy: PoliticalDistrictJSON.data(event.origin_district)
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

  defp default_banner, do: "https://media.kollective.app"


end

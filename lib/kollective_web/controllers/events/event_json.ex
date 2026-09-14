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
    banner =
      event.banner_url || Kollective.Events.EventHelpers.get_banner_url(event) ||
        default_banner()

    %{
      id: event.id,
      title: event.title,
      description: event.description,
      category: event.category || "standard",
      format: format_label(event.participation_format),
      participation_format: event.participation_format || "in_person",
      start_time: event.start_time,
      end_time: event.end_time,
      date: format_event_date(event.start_time),
      displayDate: format_display_date(event.start_time, event.end_time),
      time: format_event_time(event.start_time, event.end_time),
      timezone: event.timezone,
      status: event.event_status,

      # Visuals
      image: banner,
      banner_url: banner,
      logo_url: event.logo_url,

      # Engagement & Capacity
      participants_count: event.participants_count,
      attendeesCount: event.participants_count,
      interestedCount: 0,
      comments_count: event.comments_count,
      capacity: get_capacity(event.metadata),

      # Location string convenience and preloaded structured geography
      location_name: event.location_name,
      location_string: format_location_string(event),
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
      organizer: serialize_organizer(event.user),
      inserted_at: event.inserted_at
    }
  end

  defp format_label("in_person"), do: "In-Person"
  defp format_label("online_virtual"), do: "Online"
  defp format_label("hybrid"), do: "Hybrid"
  defp format_label(other) when is_binary(other), do: other
  defp format_label(_), do: "In-Person"

  defp format_event_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y")
  end

  defp format_event_date(_), do: nil

  defp format_display_date(%DateTime{} = start_dt, end_dt) do
    date_part = Calendar.strftime(start_dt, "%A, %b %-d")
    time_part = format_event_time(start_dt, end_dt)
    if time_part, do: "#{date_part} • #{time_part}", else: date_part
  end

  defp format_display_date(_, _), do: nil

  defp format_event_time(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    "#{Calendar.strftime(start_dt, "%H:%M")} - #{Calendar.strftime(end_dt, "%H:%M")}"
  end

  defp format_event_time(%DateTime{} = start_dt, _) do
    Calendar.strftime(start_dt, "%H:%M")
  end

  defp format_event_time(_, _), do: nil

  defp get_capacity(%{"max_participants" => max}) when is_integer(max), do: max
  defp get_capacity(%{max_participants: max}) when is_integer(max), do: max
  defp get_capacity(_), do: nil

  defp format_location_string(event) do
    cond do
      event.participation_format == "online_virtual" ->
        event.location_url || "Online"

      event.location_name && event.location_name != "" ->
        event.location_name

      event.street && event.street != "" ->
        event.street

      true ->
        "Location TBA"
    end
  end

  defp serialize_organizer(%Kollective.Accounts.User{} = user) do
    %{
      id: user.id,
      username: user.username,
      is_verified: user.is_verified
    }
  end

  defp serialize_organizer(_), do: nil

  # Helper: Handles the case where the association is fully preloaded and loaded
  defp city_name(%Kollective.Locations.City{} = city), do: city.name

  # Helper: Fallback if no city is assigned (null) or if it wasn't preloaded
  defp city_name(_), do: nil

  defp default_banner, do: "https://media.kollective.app"

  @doc """
  Serializes a single participant preview for faces row widgets.
  """
  def simple_participant(%{user: %{id: id, username: username} = user}) do
    %{
      id: id,
      username: username,
      avatar_url: Map.get(user, :avatar_url)
    }
  end

  def simple_participant(_), do: nil

  @doc """
  Serializes an event with social context (attendee preview and friends attending).
  """
  def event_with_social_context(event, attendee_preview, friends_going) do
    %{
      event: data(event),
      attendee_preview: Enum.map(attendee_preview, &simple_participant/1),
      friends_attending: Enum.map(friends_going, &simple_participant/1)
    }
  end

  @doc """
  Serializes a list of accepted participants for the event roster.
  """
  def participant_users(users) when is_list(users) do
    Enum.map(users, &participant_user/1)
  end

  def participant_user(user) do
    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar_url: user.avatar_url
    }
  end

  @doc """
  Serializes a list of collective actions for the Organize Action grid.
  """
  def actions(actions) when is_list(actions) do
    Enum.map(actions, &action_item/1)
  end

  def action_item(item) do
    %{
      id: to_string(item.id),
      name: item.title,
      description: item.description,
      category: item.category,
      participation_format: item.participation_format,
      start_time:
        if(item.start_time,
          do: Calendar.strftime(item.start_time, "%Y-%m-%dT%H:%M:%SZ"),
          else: nil
        ),
      location_name: item.location_name,
      participants_count: item.participants_count,
      is_official: not is_nil(item.organization_id),
      initiator: (item.user && item.user.username) || nil
    }
  end

  @doc """
  Serializes newly created action summary data.
  """
  def action_data(action) do
    %{
      id: to_string(action.id),
      name: action.title,
      category: action.category
    }
  end

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

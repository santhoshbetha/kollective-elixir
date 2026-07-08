defmodule Kollective.Workers.EventReminderWorker do
  @moduledoc """
  Generates notifications for upcoming events.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 2

  alias Kollective.Events.Events
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    # 1. Fetch event metadata and list of accepted attendees
    event = Events.get_event!(event_id)
    participants = Events.list_accepted_participants(event_id)

    # Pre-calculate the localized time string once to prevent inner loop CPU thrashing
    formatted_time = local_time_string(event)

    # 2. Iterate through attendees and dispatch via your unified geofenced notification engine
    Enum.each(participants, fn participant ->
      # Arguments contract: target_user_id, actor_id, type, database_attrs, websocket_payload
      Notifications.notify(
        # The recipient (Attendee)
        participant.user_id,
        # The actor (Organizer)
        event.created_by,
        # Type strictly validates against your @notification_types registry
        "event_reminder",
        %{
          event_id: event.id,
          target_id: event.id,
          target_type: "Event",
          # Consolidate dynamic properties safely inside your single JSONB metadata column
          metadata: %{
            event_title: event.name,
            local_time: formatted_time,
            # Helps React parse custom timeline icons
            sub_type: "one_hour_reminder"
          }
        },
        %{
          # Transient WebSocket payload properties read instantly by React Toast alerts
          post_id: nil,
          preview: "⏰ Reminder: '#{event.name}' is starting in 1 hour! (Time: #{formatted_time})"
        }
      )
    end)

    :ok
  end

  # Fallback helper mapping to your localized timezone conversions
  defp local_time_string(_event) do
    # Replace with your actual timezone formatting logic, e.g.:
    # Calendar.strftime(event.start_time, "%I:%M %p %Z")
    "10:00 AM IST"
  end
end

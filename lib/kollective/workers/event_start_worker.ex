# Oban Worker code that uses this timezone to send a "Starting Now"
# push notification exactly when the clock strikes 10:00 AM in the event's local zone?

# "Starting Now" notification

# To trigger a "Starting Now" notification exactly when the event begins in its local time, you use an
# Oban Worker.
# Since you stored the start_time as a utc_datetime, the worker will wake up at that exact moment
# regardless of whether the event is in India (IST) or Europe (CET).

# 1. The Oban Worker
# This worker handles the "Fan-out" of notifications to all accepted participants
# at the moment the event starts.

defmodule Kollective.Workers.EventStartWorker do
  use Oban.Worker, queue: :events, unique: [period: 60]

  alias Kollective.Events.Events
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    event = Events.get_event!(event_id)
    participants = Events.list_accepted_participants(event_id)

    # Format the localized display timestamp outside the execution loop to save CPU cycles
    formatted_time = local_time_string(event)

    # 1. Loop through attendees and trigger the unified, index-optimized notification engine
    Enum.each(participants, fn participant ->
      # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
      Notifications.notify(
        # The recipient (The attendee)
        participant.user_id,
        # The actor (The event organizer/creator)
        event.created_by,
        # Maps safely to your verified @notification_types registry
        "event_reminder",
        %{
          event_id: event.id,
          target_id: event.id,
          target_type: "Event",
          # Save dynamic variables securely inside your single JSONB metadata column
          metadata: %{
            event_title: event.title,
            local_time: formatted_time,
            # Helps React parse specialized template icons
            sub_type: "event_starting_now"
          }
        },
        %{
          # Transient WebSocket properties read instantly by React Toast alert popups
          post_id: nil,
          preview: "🚨 '#{event.title}' is starting now! (Time: #{formatted_time})"
        }
      )
    end)

    :ok
  end

  @doc "Converts UTC start time to the event's local string"
  def local_time_string(event) do
    timezone = event.timezone || "Etc/UTC"

    case DateTime.shift_zone(event.start_time, timezone) do
      {:ok, shifted_dt} ->
        Calendar.strftime(shifted_dt, "%Y-%m-%d %I:%M %p")

      _ ->
        Calendar.strftime(event.start_time, "%Y-%m-%d %I:%M %p") <> " UTC"
    end
  end
end

# 3. Why this works for India/Europe/Global:

#    UTC Synchronization: Oban runs on the server's clock (UTC). If an event is at 10:00 AM Asia/Kolkata, your DB stores 04:30 AM UTC. Oban wakes up at 04:30 UTC, which is exactly when the clock in India strikes 10:00 AM.
#    Reliability: If your server crashes at 9:59 AM, Oban will see the "missed" job when it reboots and send the notification immediately.
#    Real-time Push: Because Notifications.create_notification uses Phoenix.PubSub, the user's React app will show the "Event Starting!" toast the millisecond the worker runs.

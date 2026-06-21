#Proactive Follow-up: You now have the full lifecycle from Creating to Exporting! Should we add
#"Event Reminders" for the organizer so they get a summary of who is attending 24 hours before the event starts?

#To wrap up the Event Lifecycle, we’ll build an Oban worker that sends a "Pre-Event Summary" to the organizer.
#This gives them a "Heads Up" with the final headcount 24 hours before the event starts.

#Pre-Event Summary" to the organizer

#1. The Organizer Summary Worker
#This worker fetches the counts for "Going" and "Maybe" and sends a notification specifically to the
#created_by user.

defmodule Kollective.Workers.OrganizerSummaryWorker do
  use Oban.Worker, queue: :events

  alias Kollective.Events.Events
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id}}) do
    event = Events.get_event!(id)

    # 1. Fetch current stats
    going = event.participants_count
    pending = event.participation_request_count

    # 2. Notify the Organizer (created_by)
    Notifications.notify(
      event.created_by,       # The recipient (The Organizer)
      event.created_by,       # The actor (System self-notification tracking)
      "event_reminder",       # Type must match our strict @notification_types registry string
      %{
        event_id: event.id,
        target_id: event.id,
        target_type: "Event",
        # Store explicit summary parameters securely inside your JSONB metadata block
        metadata: %{
          event_title: event.name,
          going_count: going,
          pending_count: pending
        }
      },
      %{
        # Transient WebSocket payload properties read instantly by React Toast elements
        post_id: nil,
        preview: "Your event starts in 24h! You have #{going} people going."
      }
    )

    :ok
  end
end

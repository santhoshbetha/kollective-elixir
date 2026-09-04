# lib/kollective/workers/notify_attendees_worker.ex
defmodule Kollective.Workers.NotifyAttendeesWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Kollective.Repo
  alias Kollective.Events.Event
  alias Kollective.Notifications.Notifications
  alias Kollective.Events.Events

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    case Repo.get(Event, event_id) do
      nil ->
        {:error, :not_found}

      event ->
        notify_attendees_of_time_change(event)
        :ok
    end
  end

  def notify_attendees_of_time_change(event) do
    participants = Events.list_accepted_participants(event.id)
    # Replace with your dynamic timezone helper: EventHelpers.local_time_string(event)
    formatted_time = "10:00 AM IST"

    Enum.each(participants, fn p ->
      # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
      Notifications.notify(
        # The recipient (The registered attendee)
        p.user_id,
        # The actor (The organizer who rescheduled the calendar)
        event.created_by,
        # Type validated against your strict snake_case registry list
        "event_update",
        %{
          event_id: event.id,
          target_id: event.id,
          target_type: "Event",
          metadata: %{
            event_title: event.title,
            new_time: formatted_time
          }
        },
        %{
          post_id: nil,
          preview: "📅 Time changed for '#{event.title}'. New schedule: #{formatted_time}."
        }
      )
    end)
  end
end

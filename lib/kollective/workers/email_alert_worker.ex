# lib/kollective/workers/event_alert_worker.ex

# Oban Worker for these email alerts now to keep your API response times fast

#To keep your API response times under 100ms, you should never send emails directly during a request.
#Instead, you "fire and forget" a job into Oban.

# Create the Worker
#This worker handles the actual email delivery. If the mail server is down, Oban will automatically retry
# it later without affecting the user who created the event.

defmodule Kollective.Workers.EventAlertWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 5
  alias Kollective.Events.Events
  alias Kollective.Accounts.Accounts
  alias Kollective.Moderation.Moderation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id, "user_id" => user_id}}) do
    # Fetch the data needed for the email
    event = Events.get_event!(event_id)
    user = Accounts.get_user!(user_id)

    # Trigger the email delivery
    Moderation.notify_admin_of_flagged_event(event, user)

    :ok
  end
end

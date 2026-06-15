# Mention processing involves regex and multiple DB lookups. Use Oban to keep your API response times fast.
# lib/kollective/workers/mention_notification_worker.ex
defmodule Kollective.Workers.MentionNotificationWorker do
  use Oban.Worker, queue: :notifications
  alias Kollective.{Repo, Accounts, Interactions.Notification}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"actor_id" => actor_id, "text" => text} = args}) do
    mentioned_ids = Accounts.find_mentioned_users(text)
    recipients = Enum.reject(mentioned_ids, &(&1 == actor_id))

    Enum.each(recipients, fn recipient_id ->
      Kollective.Interactions.Notifier.broadcast_notification(
        args["actor_id"],
        recipient_id,
        "mention",
        args
      )
    end)

    :ok
  end
end

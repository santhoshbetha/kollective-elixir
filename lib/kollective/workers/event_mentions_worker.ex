# lib/kollective/workers/event_mentions_worker.ex
defmodule Kollective.Workers.EventMentionsWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query
  alias Kollective.Repo
  # Adjust to match your application event schema
  alias Kollective.Events.Event
  # Adjust to match your application user schema
  alias Kollective.Accounts.User
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    case Repo.get(Event, event_id) do
      nil ->
        {:error, :event_not_found}

      event ->
        # 1. Parse unique username strings from description text
        mentioned_usernames = parse_mention_strings(event.description || "")

        if Enum.any?(mentioned_usernames) do
          # 🚀 FIX: Convert strings to actual user database nodes in a single batch lookup
          mentioned_users = Repo.all(from u in User, where: u.username in ^mentioned_usernames)

          # 2. Iterate through found database user profiles and notify them
          Enum.each(mentioned_users, fn recipient ->
            # SELF-NOTIFICATION GUARD
            if recipient.id != event.user_id do
              {:ok, notification} =
                Notifications.notify(
                  recipient.id,
                  event.user_id,
                  "mention",
                  %{
                    event_id: event.id,
                    target_id: event.id,
                    target_type: "Event"
                  },
                  %{
                    event_id: event.id,
                    preview:
                      "mentioned you in an event: \"#{String.slice(event.description || "", 0, 30)}...\""
                  }
                )

              KollectiveWeb.Endpoint.broadcast(
                "user_notifications:#{recipient.id}",
                "new_notification",
                %{notification: notification}
              )
            end
          end)
        end

        :ok
    end
  end

  defp parse_mention_strings(text) do
    Regex.scan(~r/@[[:alnum:]_]+/, text)
    |> List.flatten()
    |> Enum.map(&String.replace(&1, "@", ""))
    |> Enum.uniq()
  end
end

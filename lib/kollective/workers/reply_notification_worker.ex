# lib/kollective/workers/reply_notification_worker.ex
defmodule Kollective.Workers.ReplyNotificationWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kollective.Repo
  alias Kollective.Posts.Post
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"recipient_id" => recipient_id, "actor_id" => actor_id, "reply_id" => reply_id}
      }) do
    if is_nil(recipient_id) or recipient_id == actor_id do
      :ok
    else
      case Repo.get(Post, reply_id) do
        nil ->
          {:error, :reply_not_found}

        reply ->
          # Executes safely within Oban's sandbox-compatible environment
          Notifications.notify_reply(recipient_id, actor_id, reply)
          :ok
      end
    end
  end
end

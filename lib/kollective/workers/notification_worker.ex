defmodule Kollective.Workers.NotificationWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "target_user_id" => target_user_id,
          "actor_id" => actor_id,
          "type" => type,
          "attrs" => attrs,
          "data_payload" => data_payload
        }
      }) do
    # ASYNC DISPATCH: Reuses your core notifications file logic inside background threads
    # This safely processes muted filters, saves to DB, and fires the WebSocket toasts
    case Notifications.notify(target_user_id, actor_id, type, attrs, data_payload) do
      {:ok, _notification} -> :ok
      # Safety discard: No need to retry self-actions or muted users
      {:error, :muted_or_self_action} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{
        args: %{"recipient_id" => recipient_id, "actor_id" => actor_id, "post_id" => post_id}
      }) do
    alias Kollective.Repo
    alias Kollective.Posts.Post

    case Repo.get(Post, post_id) do
      # Discard job if the target post was deleted before the worker picked it up
      nil ->
        :ok

      post ->
        case Notifications.notify_reply(recipient_id, actor_id, post) do
          {:ok, _notification} -> :ok
          {:error, :thread_silenced_or_self} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end

# Mention processing involves regex and multiple DB lookups. Use Oban to keep your API response times fast.
# lib/kollective/workers/mention_notification_worker.ex
defmodule Kollective.Workers.MentionNotificationWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kollective.Repo
  alias Kollective.Posts.Post
  alias Kollective.Notifications.Notification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"actor_id" => actor_id, "post_id" => post_id}}) do
    # 1. Fetch the unified post and preload its parent data to inspect context locks
    case Repo.get(Post, post_id) do
      nil ->
        # If the post was deleted by a moderator before the job ran, discard cleanly
        :ok

      post ->
        # 2. Extract parent author details to prevent the double-notification bug
        parent_author_id = get_parent_author_id(post)

        # 3. Pull our pre-calculated JSONB mentions array from the schema field
        # Loop through them to deliver database records and live WebSockets
        Enum.each(post.mentions || [], fn mention_map ->
          recipient_id = mention_map["id"] || mention_map[:id]

          # ENFORCE CRITICAL SAFETY GUARDS
          # Guard A: Don't notify the author of their own actions
          # Guard B: Don't double-notify the parent author if they were already alerted by reply trackers
          if recipient_id != actor_id && recipient_id != parent_author_id do
            deliver_mention_notification(recipient_id, actor_id, post.id)
          end
        end)

        :ok
    end
  end

  # Orchestrates full persistent and transient notifications delivery lines
  defp deliver_mention_notification(recipient_id, actor_id, post_id) do
    # 1. Save the persistent audit log row to the database for the history tab
    # Maps directly to your Kollective.Interactions context setup
    {:ok, notification} =
      %Notification{}
      |> Notification.changeset(%{
        user_id: recipient_id,
        actor_id: actor_id,
        post_id: post_id,
        type: "mention"
      })
      |> Repo.insert()

    # 2. CRITICAL REAL-TIME ROUTING BREAKOUT
    # Broadcast across your system's unified notification stream so React displays a Toast popup live
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "user_notifications:#{recipient_id}",
      {:new_notification, notification}
    )
  end

  defp get_parent_author_id(post) do
    if post.in_reply_to_id do
      case Repo.get(Post, post.in_reply_to_id) do
        nil -> nil
        parent -> parent.user_id
      end
    else
      nil
    end
  end
end

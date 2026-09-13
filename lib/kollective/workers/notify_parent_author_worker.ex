# lib/kollective/workers/notify_parent_author_worker.ex
defmodule Kollective.Workers.NotifyParentAuthorWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kollective.Repo
  # Adjust according to your application namespaces
  alias Kollective.Posts.Post
  alias Kollective.Notifications.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"reply_id" => reply_id}}) do
    case Repo.get(Post, reply_id) do
      nil ->
        {:error, :reply_not_found}

      post ->
        if post.in_reply_to_id do
          parent = Repo.get(Post, post.in_reply_to_id)

          if parent && parent.user_id && post.user_id && parent.user_id != post.user_id do
            Notifications.notify_reply(
              parent.user_id,
              post.user_id,
              post
            )
          end
        end

        :ok
    end
  end
end

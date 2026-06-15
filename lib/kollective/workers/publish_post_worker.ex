# This worker handles the "Push" to the live feed once the scheduled time arrives.
defmodule Kollective.Workers.PublishPostWorker do
  use Oban.Worker, queue: :default

  def perform(%Oban.Job{args: %{"post_id" => post_id}}) do
    # 1. Fetch the post
    post = Kollective.Repo.get!(Kollective.Post, post_id) |> Kollective.Repo.preload(:author)

    # 2. Broadcast to the "Push" channel so active users see it appear
    KollectiveWeb.Endpoint.broadcast("feed:public", "new_post_available", %{
      id: post.id,
      author: post.author.username
    })

    :ok
  end
end

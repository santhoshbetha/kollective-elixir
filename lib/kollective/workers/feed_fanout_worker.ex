# The Asynchronous Fan-Out Worker
# When a post is published, your main transaction should not distribute the post to
# 10,000 followers synchronously—this would block your API connection pool and cause a timeout.
# Instead, queue a fast background job using Oban.
defmodule Kollective.Workers.FeedFanoutWorker do
  use Oban.Worker, queue: :default, max_attempts: 2
  alias Kollective.Repo
  # alias Kollective.Chat.Participant # Reuse structural queries or use a dedicated helper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id, "author_id" => author_id}}) do
    import Ecto.Query

    # 1. Gather all follower IDs for this author
    follower_ids =
      from(r in Kollective.Accounts.UserRelationship,
        where: r.target_id == ^author_id and r.type == "follow",
        select: r.source_id
      )
      |> Repo.all()

    # 2. Bulk insert rows into the Home Feed Cache table
    # This is a high-speed bulk database insertion pass
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(follower_ids, fn follower_id ->
        %{
          user_id: follower_id,
          post_id: post_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Insert in chunks of 1,000 to prevent hitting Postgres parameter limits
    Enum.chunk_every(entries, 1000)
    |> Enum.each(fn chunk ->
      Repo.insert_all("home_feed_entries", chunk, on_conflict: :nothing)
    end)

    # 3. Stream real-time alerts over WebSockets to currently active followers
    Enum.each(follower_ids, fn follower_id ->
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "timeline:home:#{follower_id}",
        {:new_timeline_post, %{post_id: post_id}}
      )
    end)

    :ok
  end
end

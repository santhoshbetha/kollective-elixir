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
    if is_nil(author_id) do
      :ok
    else
      import Ecto.Query

      # 1. Gather all follower IDs for this author + include author for their own home feed cache
      follower_ids =
        from(r in Kollective.Accounts.UserRelationship,
          where: r.target_id == ^author_id and r.type == "follow",
          select: r.source_id
        )
        |> Repo.all()

      all_recipient_ids = Enum.uniq([author_id | follower_ids])

      # 2. Bulk insert rows into the Home Feed Cache table
      # This is a high-speed bulk database insertion pass
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(all_recipient_ids, fn recipient_id ->
          %{
            user_id: recipient_id,
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

      # 3. Stream real-time alerts over WebSockets to currently active followers and the author
      Enum.each(all_recipient_ids, fn recipient_id ->
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "timeline:home:#{recipient_id}",
          {:new_timeline_post, %{post_id: post_id}}
        )
      end)

      :ok
    end
  end
end

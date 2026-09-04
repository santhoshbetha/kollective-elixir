# This worker handles the "Push" to the live feed once the scheduled time arrives.
# lib/kollective/workers/publish_post_worker.ex
defmodule Kollective.Workers.PublishPostWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Kollective.Repo
  # FIX: Corrected target schema module namespace naming error
  alias Kollective.Posts.Post

  @impl Oban.Worker
  @doc """
  Executes the background release sequence for scheduled future posts.
  Promotes the row status atomically and broadcasts full content cards warning-free.
  """
  def perform(%Oban.Job{args: %{"post_id" => post_id}}) do
    # 1. Fetch the post row profile securely using your sortable primary identifier
    case Repo.get(Post, post_id) do
      nil ->
        # If the author deleted their draft before the launch window arrived, cancel gracefully
        :ok

      %Post{} = post ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        # 2. ATOMIC STATUS MUTATION PASS
        # Promote the post row parameter status out of "scheduled" and into active "published" standing
        case post |> Post.changeset(%{status: "published", published_at: now}) |> Repo.update() do
          {:ok, updated_post} ->
            # 3. HYDRATE ASSOCIATIONS AND MEDIA CAROUSELS IN ONE BATCH PASS
            hydrated_post = Repo.preload(updated_post, [:author, :attachments])

            # 4. CHRONOLOGICAL DISPATCH INTERCEPTOR
            # Only push live to scrollers if the item is explicitly marked as public visibility
            if Map.get(hydrated_post, :visibility, "public") == "public" do
              # Serialize the data payload using your warning-free PostJSON contract
              serialized_payload =
                KollectiveWeb.PostJSON.show(%{
                  post: hydrated_post,
                  likes_count: 0,
                  has_liked: false
                })

              # FIX: Route the full content map card straight down your global timeline stream
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                # Corrected target channel
                "timeline:global",
                {:new_post_registered, serialized_payload}
              )
            end

            # 5. ENQUEUE REUSABLE BACKGROUND FEED FAN-OUT TASKS
            # Triggers your high-velocity user timeline background replication workers out-of-band
            if Map.get(hydrated_post, :visibility) == "public" do
              %{"post_id" => hydrated_post.id, "author_id" => hydrated_post.user_id}
              |> Kollective.Workers.FeedFanoutWorker.new()
              |> Oban.insert!()
            end

            :ok

          {:error, changeset} ->
            # Return standard error tuples so Oban can safely manage its retry and backoff curves
            {:error, changeset}
        end
    end
  end
end

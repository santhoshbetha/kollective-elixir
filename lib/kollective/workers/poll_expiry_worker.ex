# l"Poll Expiry" using Oban to automatically push the final results when the timer hits zero

#This worker handles the "Final Push." It fetches the final counts and broadcasts them to any active React users.
defmodule Kollective.Workers.PollExpiryWorker do
  use Oban.Worker, queue: :default

  def perform(%Oban.Job{args: %{"poll_id" => poll_id}}) do
    # 1. Fetch the final state
    case Kollective.Polls.Polls.get_poll_results(poll_id) do
      nil -> :ok
      poll ->
        # 2. Broadcast "Poll Closed" status to React
        KollectiveWeb.Endpoint.broadcast("poll:#{poll_id}", "poll_expired", %{
          id: poll.id,
          final_results: poll.options
        })
        :ok
    end
  end
end

defmodule KollectiveWeb.Admin.ObanTelemetryController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.Repo

  @doc """
  GET /api/v1/admin/telemetry/oban
  Compiles real-time background queue metrics from the local node.
  """
  def index(conn, _params) do
    # 1️⃣ Aggregate total jobs grouped by their runtime execution state pools [1]
    state_counts =
      from(j in "oban_jobs",
        select: {j.state, count(j.id)},
        group_by: j.state
      )
      |> Repo.all()
      |> Map.new()

    # 2️⃣ Fetch recent failure incidents to help admins trace exceptions
    recent_errors =
      from(j in "oban_jobs",
        where: j.state in ["retryable", "discarded"],
        select: %{
          id: j.id,
          queue: j.queue,
          worker: j.worker,
          state: j.state,
          errors: j.errors,
          args: j.args,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          attempted_at: j.attempted_at,
          inserted_at: j.inserted_at
        },
        order_by: [desc: j.attempted_at],
        limit: 15
      )
      |> Repo.all()

    json(conn, %{
      data: %{
        summary: %{
          executing: Map.get(state_counts, "executing", 0),
          completed: Map.get(state_counts, "completed", 0),
          retryable: Map.get(state_counts, "retryable", 0),
          discarded: Map.get(state_counts, "discarded", 0)
        },
        recent_failures: recent_errors
      }
    })
  end
end

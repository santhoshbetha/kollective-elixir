defmodule Kollective.Workers.IncidentDistributionWorker1 do
  # use Oban.Worker, queue: :moderation_sync, max_attempts: 5
  use Oban.Worker, queue: :default, max_attempts: 5
  require Logger

  alias Kollective.Repo
  # Replace with your actual database incident schema namespace mapping
  alias Kollective.Moderation.Incident

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"incident_id" => incident_id}}) do
    # 1️⃣ Fetch the report context row from your local database node disk storage
    case Repo.get(Incident, incident_id) do
      nil ->
        Logger.warning(
          "⚠️ [MESH WORKER]: Incident ##{incident_id} not found on local disk storage."
        )

        :ok

      incident ->
        Logger.info(
          "📡 [MESH WORKER]: Enqueueing distributed mesh sync path for incident ##{incident.id}"
        )

        # 2️⃣ Execute the inter-node RPC cross-cluster routing matrix [1]
        Kollective.Moderation.MeshRouter.distribute_incident_across_mesh(incident)
        :ok
    end
  end
end

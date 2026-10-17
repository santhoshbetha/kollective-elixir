defmodule Kollective.Workers.IncidentDistributionWorker do
  use Oban.Worker, queue: :default, max_attempts: 5
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.Incident

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"incident_id" => incident_id}}) do
    case Repo.get(Incident, incident_id) do
      nil ->
        :ok

      incident ->
        # 🔒 PROTECTED CRYPTOGRAPHIC REPLICATION EXECUTION
        try do
          Kollective.Moderation.MeshRouter.distribute_incident_across_mesh(incident)
          :ok
        catch
          # Intercept explicit Erlang Mnesia distributed memory transaction crash boundaries
          :exit, {:aborted, reason} ->
            error_msg =
              "🚨 [MNESIA MESH FATAL]: Distributed replication transaction rolled back over cluster node. Reason: #{inspect(reason)}"

            Logger.error(error_msg)

            # Throwing an explicit structured error string allows Oban's error recorder to save it to disk
            raise RuntimeError, message: error_msg

          kind, error ->
            error_msg =
              "❌ [MESH WORKER CRITICAL]: Pipeline failed during sync handshakes: #{inspect(kind)} -> #{inspect(error)}"

            Logger.error(error_msg)
            raise RuntimeError, message: error_msg
        end
    end
  end
end

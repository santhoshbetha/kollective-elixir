defmodule Kollective.Database.MnesiaLeaseReaper do
  use GenServer
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.Incident

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    # Schedule the reaper worker cycle loop to kick off immediately
    schedule_reap_cycle()
    {:ok, opts}
  end

  @impl true
  def handle_info(:execute_reap, state) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    # 1️⃣ Read all incident entries out of high speed local cluster memory maps
    expired_incident_ids =
      :mnesia.dirty_select(:scholar_incidents, [
        {
          # Structural Match Spec Tuple targeting record parameters
          {:scholar_incidents, :"$1", :_, :_, :_, :_, :_, :"$2", :"$3"},
          # Conditions: leased_by_id ($2) is not nil AND leased_until ($3) < now_unix
          [{:"/=", :"$2", nil}, {:<, :"$3", now_unix}],
          # Return value allocation: Just return the record IDs
          [:"$1"]
        }
      ])

    unless Enum.empty?(expired_incident_ids) do
      Logger.info(
        "🧹 [LEASE REAPER]: Identified #{length(expired_incident_ids)} abandoned operator leases. Evicting locks..."
      )

      Enum.each(expired_incident_ids, fn id -> reap_expired_lease(id) end)
    end

    schedule_reap_cycle()
    {:noreply, state}
  end

  defp reap_expired_lease(incident_id) do
    # 1️⃣ Clear memory lease lock inside Mnesia cluster
    :mnesia.activity(:transaction, fn ->
      read_result =
        case :mnesia.read(:scholar_incidents, incident_id) do
          [] -> :mnesia.read(:scholar_incidents, to_string(incident_id))
          res -> res
        end

      case read_result do
        [record] ->
          element = Tuple.to_list(record)
          updated_record = element |> List.replace_at(7, nil) |> List.replace_at(8, nil)
          :mnesia.write(List.to_tuple(updated_record))

        [] ->
          :ok
      end
    end)

    # 2️⃣ Clear lease tracking metrics inside PostgreSQL (if record exists)
    try do
      case Repo.get(Incident, incident_id) do
        nil ->
          :ok

        incident ->
          incident
          |> Incident.changeset(%{leased_by_id: nil, leased_until: nil})
          |> Repo.update()
      end
    rescue
      _ -> :ok
    end

    # 3️⃣ Broadcast notification to admin dashboards
    KollectiveWeb.Endpoint.broadcast!(
      "admin_notifications:global",
      "incident_lease_dropped",
      %{
        incident_id: to_string(incident_id),
        status: "pending",
        leased_by_id: nil
      }
    )
  rescue
    error ->
      Logger.error(
        "❌ [REAPER CRITICAL]: Failed to unlock incident ID #{incident_id}: #{inspect(error)}"
      )
  end

  defp schedule_reap_cycle do
    # Run the sweeping pattern every 60 seconds consistently
    Process.send_after(self(), :execute_reap, 60_000)
  end
end

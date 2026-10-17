defmodule Kollective.MnesiaHydrator do
  use GenServer
  require Logger
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Moderation.Incident

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(opts) do
    # Wait a brief moment for libcluster to stabilize node connections before hydrating
    Process.send_after(self(), :hydrate_cluster, 3000)
    {:ok, opts}
  end

  def handle_info(:hydrate_cluster, state) do
    if :mnesia.system_info(:is_running) == :yes and
         :scholar_incidents in :mnesia.system_info(:tables) do
      case :mnesia.table_info(:scholar_incidents, :size) do
        0 ->
          Logger.info("🔄 [Mnesia] Table empty. Restoring active incidents from PostgreSQL.")
          hydrate_from_postgres()

        size ->
          Logger.info("✅ [Mnesia] Table already has #{size} records. Skipping hydration.")
      end
    end

    {:noreply, state}
  end

  defp hydrate_from_postgres do
    active_incidents =
      from(i in Incident, where: i.status == "pending")
      |> Repo.all()

    Enum.each(active_incidents, fn incident ->
      inserted_at_unix =
        case incident.inserted_at do
          %DateTime{} = dt -> DateTime.to_unix(dt)
          %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.to_unix()
          _ -> System.system_time(:second)
        end

      leased_until_unix =
        if incident.leased_until, do: DateTime.to_unix(incident.leased_until), else: nil

      mnesia_record = {
        :scholar_incidents,
        to_string(incident.id),
        incident.status,
        incident.country_code,
        to_string(incident.target_username),
        incident.description,
        inserted_at_unix,
        if(incident.leased_by_id, do: to_string(incident.leased_by_id), else: nil),
        leased_until_unix
      }

      :mnesia.activity(:transaction, fn ->
        :mnesia.write(mnesia_record)
      end)
    end)

    Logger.info("[Mnesia] Hydration complete! Loaded #{length(active_incidents)} active items.")
  end
end

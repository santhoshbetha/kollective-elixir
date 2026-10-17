defmodule Kollective.Database.MnesiaRehydrationEngine do
  use GenServer
  import Ecto.Query
  require Logger

  alias Kollective.Repo
  alias Kollective.Chats.Conversation
  alias Kollective.Moderation.Incident

  @tables [:scholar_incidents, :node_sovereign_operators, :distributed_chat_groups]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true)
    Process.send_after(self(), :cold_boot_postgres_check, 3000)
    {:ok, %{is_hydrating: false}}
  end

  @impl true
  def handle_info(:cold_boot_postgres_check, state) do
    # 1️⃣ HYDRATE ACTIVE SCHOLAR INCIDENTS
    case :mnesia.table_info(:scholar_incidents, :size) do
      0 ->
        Logger.info(
          "🔄 [REHYDRATION COLD BOOT]: Mnesia ':scholar_incidents' cache is empty. Restoring active queues from Postgres..."
        )

        hydrate_incidents_from_postgres()

      size ->
        Logger.info(
          "✅ [REHYDRATION COLD BOOT]: Incident mesh has #{size} records. Skipping database read."
        )
    end

    # 2️⃣ HYDRATE DISTRIBUTED CHAT GROUPS
    case :mnesia.table_info(:distributed_chat_groups, :size) do
      0 ->
        Logger.info(
          "🔄 [REHYDRATION COLD BOOT]: Mnesia ':distributed_chat_groups' cache is empty. Restoring active rooms from Postgres..."
        )

        hydrate_chats_from_postgres()

      size ->
        Logger.info(
          "✅ [REHYDRATION COLD BOOT]: Chat mesh has #{size} records. Skipping database read."
        )
    end

    {:noreply, state}
  end

  # --- Libcluster Handles Node Ups and Downs (Unchanged) ---
  @impl true
  def handle_info({:nodeup, remote_node}, state) do
    send(self(), {:trigger_sync_sequence, remote_node})
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _remote_node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:trigger_sync_sequence, remote_node}, state) do
    if state.is_hydrating,
      do: {:noreply, state},
      else: {:noreply, execute_rehydration_handshake(remote_node, state)}
  end

  # --- Internal Mnesia Mesh Synchers ---
  defp execute_rehydration_handshake(remote_node, state) do
    case :mnesia.change_config(:extra_db_nodes, [remote_node]) do
      {:ok, _} ->
        case :mnesia.wait_for_tables(@tables, 10_000) do
          :ok ->
            %{state | is_hydrating: false}

          {:timeout, _bad_tables} ->
            force_atomic_table_reseed(remote_node, @tables)
            %{state | is_hydrating: false}

          {:error, _r} ->
            %{state | is_hydrating: false}
        end

      _error ->
        push_local_hydration_outward(remote_node)
        %{state | is_hydrating: false}
    end
  end

  defp force_atomic_table_reseed(_remote_node, tables) do
    Enum.each(tables, fn table ->
      case :mnesia.add_table_copy(table, Node.self(), :disc_copies) do
        {:atomic, :ok} ->
          :ok

        {:aborted, {:already_exists, _, _}} ->
          :mnesia.del_table_copy(table, Node.self())
          :mnesia.add_table_copy(table, Node.self(), :disc_copies)

        _error ->
          :ok
      end
    end)
  end

  defp push_local_hydration_outward(remote_node) do
    :rpc.call(remote_node, :mnesia, :change_config, [:extra_db_nodes, [Node.self()]])
    Enum.each(@tables, fn table -> :mnesia.add_table_copy(table, remote_node, :disc_copies) end)
  end

  # --- Postgres Hydrators ---
  defp hydrate_incidents_from_postgres do
    # Pull items currently awaiting attention to maintain zero-lag lookup tables
    active_incidents = from(i in Incident, where: i.status == "pending") |> Repo.all()

    Enum.each(active_incidents, fn incident ->
      inserted_at_unix =
        case incident.inserted_at do
          %DateTime{} = dt -> DateTime.to_unix(dt)
          %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.to_unix()
          _ -> nil
        end

      leased_until_unix =
        if incident.leased_until, do: DateTime.to_unix(incident.leased_until), else: nil

      # 🎯 FIXED ELEMENT POSITIONS: Matches your initialize_sovereign_tables schema specification perfectly!
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

      :mnesia.transaction(fn -> :mnesia.write(mnesia_record) end)
    end)

    Logger.info(
      "✨ [REHYDRATION ENGINE]: Restored #{length(active_incidents)} active pending incidents out of Postgres."
    )
  end

  defp hydrate_chats_from_postgres do
    conversations = from(c in Conversation, order_by: [desc: c.inserted_at]) |> Repo.all()

    Enum.each(conversations, fn conversation ->
      inserted_at_iso =
        case conversation.inserted_at do
          %DateTime{} = dt -> DateTime.to_iso8601(dt)
          %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
          nil -> DateTime.utc_now() |> DateTime.to_iso8601()
        end

      description = Map.get(conversation, :description, "") || ""
      title = conversation.title || "Group Chat"

      mnesia_record = {
        :distributed_chat_groups,
        to_string(conversation.id),
        title,
        description,
        "cause",
        inserted_at_iso
      }

      :mnesia.transaction(fn -> :mnesia.write(mnesia_record) end)
    end)

    Logger.info(
      "✨ [REHYDRATION ENGINE]: Restored #{length(conversations)} distributed chat rooms out of Postgres."
    )
  end
end

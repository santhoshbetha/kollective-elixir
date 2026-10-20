defmodule Kollective.Database.MnesiaClusterCoordinator do
  use GenServer
  @compile {:no_warn_undefined, :mnesia}
  require Logger

  @doc """
  Starts the Mnesia sync process. Monitored directly in your core supervisor tree.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # 1️⃣ Subscribe to internal node cluster changes emitted by libcluster
    :net_kernel.monitor_nodes(true)

    # 2️⃣ Detect active cluster peers already connected via Erlang distribution
    active_peers = Node.list()

    if active_peers != [] do
      Logger.info(
        "📡 [MNESIA CLUSTER]: Joining active cluster via peers: #{inspect(active_peers)}"
      )

      :mnesia.start()

      case :mnesia.change_config(:extra_db_nodes, active_peers) do
        {:ok, _} ->
          _ = :mnesia.change_table_copy_type(:schema, Node.self(), :disc_copies)
          copy_cluster_tables_to_local()

        error ->
          Logger.warning(
            "⚠️ [MNESIA CLUSTER]: Failed to join peer schemas, initializing local: #{inspect(error)}"
          )

          initialize_local_schema_and_tables()
      end
    else
      initialize_local_schema_and_tables()
    end

    # 3️⃣ Trigger a soft synchronization sync against any already active nodes
    send(self(), :sync_existing_cluster_nodes)

    {:ok, %{}}
  end

  @impl true
  def handle_info({:nodeup, remote_node}, state) do
    Logger.info(
      "📡 [MNESIA MESH]: Discovered new node: #{remote_node}. Synchronizing replica schemas..."
    )

    # Connect the remote node to our Mnesia cluster context
    case :mnesia.change_config(:extra_db_nodes, [remote_node]) do
      {:ok, _} ->
        # Mirror table structures to the new node's disk/RAM layers
        replicate_tables_to_node(remote_node)

      error ->
        Logger.error(
          "❌ [MNESIA CRITICAL]: Handshake rejected with node #{remote_node}: #{inspect(error)}"
        )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, remote_node}, state) do
    Logger.warning(
      "🔌 [MNESIA MESH]: Node disconnected: #{remote_node}. Healing cluster routing tables..."
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_existing_cluster_nodes, state) do
    # Mount any nodes libcluster has already connected via Erlang distribution
    Enum.each(Node.list(), fn active_node ->
      case :mnesia.change_config(:extra_db_nodes, [active_node]) do
        {:ok, _} ->
          replicate_tables_to_node(active_node)

        _ ->
          :ok
      end
    end)

    {:noreply, state}
  end

  defp initialize_local_schema_and_tables do
    # Ensure local schema exists or create it safely
    _ = :mnesia.stop()
    _ = :mnesia.create_schema([Node.self()])
    _ = :mnesia.start()
    initialize_sovereign_tables()
  end

  defp copy_cluster_tables_to_local do
    tables = [
      :scholar_incidents,
      :node_sovereign_operators,
      :distributed_chat_groups,
      :distributed_appeals
    ]

    Enum.each(tables, fn table ->
      case :mnesia.add_table_copy(table, Node.self(), :disc_copies) do
        {:atomic, :ok} ->
          Logger.info("✅ [MNESIA SYNC]: Local node synced table copy for #{table}")

        {:aborted, {:already_exists, _, _}} ->
          :ok

        err ->
          Logger.warning("⚠️ [MNESIA SYNC]: Table copy for #{table} deferred: #{inspect(err)}")
      end
    end)
  end

  # --- Private Database Definition Engines ---

  defp initialize_sovereign_tables() do
    # Table A: Active Scholar Integrity Incidents
    # Attributes mirror your relational Ecto target schemas exactly
    :mnesia.create_table(:scholar_incidents, [
      {:type, :set},
      # Persists to local server NVMe/SSD disks safely
      {:disc_copies, [Node.self()]},
      {:attributes,
       [
         :id,
         :status,
         :country_code,
         :target_username,
         :description,
         :inserted_at,
         :leased_by_id,
         :leased_until
       ]}
    ])

    # Table B: Decentralized Local Sovereignty Operators Whitelists
    :mnesia.create_table(:node_sovereign_operators, [
      {:type, :set},
      {:disc_copies, [Node.self()]},
      {:attributes, [:username, :role, :granted_by, :inserted_at]}
    ])

    :mnesia.create_table(:distributed_chat_groups, [
      {:type, :set},
      {:disc_copies, [Node.self()]},
      {:attributes, [:id, :title, :description, :type, :inserted_at]}
    ])

    :mnesia.create_table(:distributed_appeals, [
      {:type, :set},
      {:disc_copies, [Node.self()]},
      {:attributes, [:id, :incident_id, :user_id, :reason, :status, :country_code, :inserted_at]}
    ])
  end

  defp replicate_tables_to_node(remote_node) do
    _ = :mnesia.change_table_copy_type(:schema, remote_node, :disc_copies)

    tables = [
      :scholar_incidents,
      :node_sovereign_operators,
      :distributed_chat_groups,
      :distributed_appeals
    ]

    Enum.each(tables, fn table ->
      case :mnesia.add_table_copy(table, remote_node, :disc_copies) do
        {:atomic, :ok} ->
          Logger.info("✅ [MNESIA SYNC]: Table #{table} mirrored to #{remote_node}")

        {:aborted, {:already_exists, _, _}} ->
          :ok

        err ->
          Logger.warning(
            "⚠️ [MNESIA SYNC]: Table #{table} replication to #{remote_node} notice: #{inspect(err)}"
          )
      end
    end)
  end
end

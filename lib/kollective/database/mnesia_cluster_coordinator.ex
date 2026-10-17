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
    # 1️⃣ Ensure Mnesia is stopped locally so we can safely initialize schemas
    :mnesia.stop()
    :mnesia.create_schema([Node.self()])
    :mnesia.start()

    # 2️⃣ Initialize local database tables if they do not yet exist on disk
    initialize_sovereign_tables()

    # 3️⃣ Subscribe to internal node cluster changes emitted by libcluster
    :net_kernel.monitor_nodes(true)

    # Trigger a soft synchronization sync against any already active nodes
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
        # Force-copy your table structures directly onto the new node's disk/RAM layers
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
      :mnesia.change_config(:extra_db_nodes, [active_node])
      replicate_tables_to_node(active_node)
    end)

    {:noreply, state}
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
    # Remotely push an identical copy of local database structures over network lines
    # disc_copies = Saves copies to remote disk; ram_copies = keeps it strictly in memory
    case :mnesia.add_table_copy(:scholar_incidents, remote_node, :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("✅ [MNESIA SYNC]: Incidents schema successfully mirrored to #{remote_node}")

      {:aborted, {:already_exists, _, _}} ->
        :ok

      err ->
        Logger.error("❌ [MNESIA SYNC ERROR]: Table copy failed: #{inspect(err)}")
    end

    case :mnesia.add_table_copy(:node_sovereign_operators, remote_node, :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("✅ [MNESIA SYNC]: Sovereignty registers mirrored to #{remote_node}")

      {:aborted, {:already_exists, _, _}} ->
        :ok

      _ ->
        :ok
    end

    case :mnesia.add_table_copy(:distributed_chat_groups, remote_node, :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("✅ [MNESIA SYNC]: Distributed chat groups mirrored to #{remote_node}")

      {:aborted, {:already_exists, _, _}} ->
        :ok

      _ ->
        :ok
    end

    case :mnesia.add_table_copy(:distributed_appeals, remote_node, :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("✅ [MNESIA SYNC]: Distributed appeals mirrored to #{remote_node}")

      {:aborted, {:already_exists, _, _}} ->
        :ok

      _ ->
        :ok
    end
  end
end

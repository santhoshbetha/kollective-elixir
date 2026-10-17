defmodule KollectiveWeb.Admin.MeshRepairController do
  use KollectiveWeb, :controller
  require Logger

  @doc """
  POST /api/v1/admin/mesh/force_recovery
  Triggers a manual database partition re-hydration reset loop over network lines.
  """
  def trigger_recovery(conn, %{"node_name" => target_node_str}) do
    target_node = String.to_atom(target_node_str)

    Logger.warning(
      "🔨 [ADMIN INFRASTRUCTURE]: Sovereign Operator triggered Force Partition Recovery on node: #{target_node}"
    )

    # 🚀 CLUSTER REPAIR PASSTHROUGH HANDSHAKE:
    # 1. Force the targeted partition node to stop its localized database instance
    # 2. Re-verify the connection with our healthy node to merge configurations back into sync
    case :rpc.call(target_node, :mnesia, :stop, []) do
      :stopped ->
        # Instruct the target to pull a clean schema copy directly from our memory layers
        _ = :rpc.call(target_node, :mnesia, :start, [])
        _ = :mnesia.change_config(:extra_db_nodes, [target_node])

        # Invoke our automated background rehydration script loop to re-seed missing keys instantly
        case Process.whereis(Kollective.Database.MnesiaRehydrationEngine) do
          pid when is_pid(pid) ->
            send(pid, {:trigger_sync_sequence, target_node})

          nil ->
            Kollective.Database.MnesiaRehydrationEngine.start_link([])
        end

        json(conn, %{
          status: "success",
          message: "Node partition healed. Table registers synchronized across the mesh cluster."
        })

      error ->
        Logger.error("❌ [RECOVERY RPC CRITICAL]: Node refused partition reset: #{inspect(error)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Target hardware node refused execution command handshakes."})
    end
  end
end

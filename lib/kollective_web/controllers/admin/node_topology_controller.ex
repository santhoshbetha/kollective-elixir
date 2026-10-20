defmodule KollectiveWeb.Admin.NodeTopologyController do
  use KollectiveWeb, :controller
  require Logger

  @doc """
  GET /api/v1/admin/mesh/topology
  Compiles real-time server cluster metrics directly out of the Erlang runtime engine.
  """
  def index(conn, _params) do
    # 1️⃣ Fetch current local server information
    local_node_name = Atom.to_string(Node.self())

    # 2️⃣ Scan all active interconnected cluster peer nodes
    # Returns an array of active Erlang node atoms
    remote_nodes = Node.list()

    # Map the remote node profiles array into clean JSON serialization blocks
    peers_metadata =
      Enum.map(remote_nodes, fn node_atom ->
        node_str = Atom.to_string(node_atom)

        # Deduce a localized country zone code tag from standard container naming conventions
        # e.g., "node_mumbai@10.0.1.5" -> "IN"
        zone_tag =
          cond do
            String.contains?(node_str, "mumbai") -> "IN"
            String.contains?(node_str, "frankfurt") -> "EU"
            String.contains?(node_str, "virginia") -> "US"
            true -> "GLOBAL"
          end

        %{
          node_name: node_str,
          zone: zone_tag,
          status: "healthy_connected",
          is_local: false
        }
      end)

    # 3️⃣ Inject the local node structure configuration as the cluster master root element
    local_metadata = %{
      node_name: local_node_name,
      zone: "LOCAL_MASTER",
      status: "healthy_connected",
      is_local: true
    }

    unified_topology_mesh = [local_metadata | peers_metadata]

    json(conn, %{
      data: %{
        cluster_size: length(unified_topology_mesh),
        network_protocol: "Erlang_Distribution_PG2",
        nodes: unified_topology_mesh
      }
    })
  end
end

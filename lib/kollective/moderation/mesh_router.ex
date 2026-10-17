defmodule Kollective.Moderation.MeshRouter do
  @doc """
  Routes an urgent alert to the nodes controlled by local operators,
  falling back to global servers if local channels are dark.
  """
  def distribute_incident_across_mesh(incident) do
    local_node = Node.self()
    # e.g., :"node_mumbai@10.0.1.5"
    target_node = incident.origin_node_atom

    if local_node == target_node do
      # Process locally inside the self-hosted node database cluster
      KollectiveWeb.Endpoint.broadcast!("admin_notifications:global", "new_incident", incident)
    else
      # 🚀 RPC HOP: Safely forward the incident alert to the remote node over the Erlang mesh
      case :rpc.call(target_node, KollectiveWeb.Endpoint, :broadcast!, [
             "admin_notifications:global",
             "new_incident",
             incident
           ]) do
        {:badrpc, _reason} ->
          # FALLBACK: Remote node is offline. Route the incident to global staff nodes instead.
          KollectiveWeb.Endpoint.broadcast_from!(
            self(),
            "admin_notifications:global",
            "new_global_incident",
            incident
          )

        _ ->
          :ok
      end
    end
  end
end

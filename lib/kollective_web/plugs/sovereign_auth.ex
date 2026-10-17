defmodule KollectiveWeb.Plugs.SovereignAuth do
  use KollectiveWeb, :controller

  @doc """
  🛡️ SOVEREIGN ACCESS PLUG INTERCEPTOR:
  Bypasses centralized authorization registers. The server owner defines
  who holds admin keys on this physical machine node.
  """
  def init(opts), do: opts

  def call(conn, opts) do
    verify_node_sovereignty_clearance(conn, opts)
  end

  def verify_node_sovereignty_clearance(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    # Read the hardcoded owner list defined on this node's isolated disk configuration env
    node_owners = System.get_env("NODE_SOVEREIGN_OWNER_USERNAMES") || ""
    allowed_owners = String.split(node_owners, ",")

    is_node_owner? = user && user.username in allowed_owners

    # Check Mnesia decentralized operator whitelist for this node
    is_whitelisted_node_operator? =
      if user do
        try do
          case :mnesia.dirty_read(:node_sovereign_operators, user.username) do
            [record] ->
              role = Enum.at(Tuple.to_list(record), 2)
              role in ["admin", "root", "moderator", "staff"]

            _ ->
              false
          end
        rescue
          _ -> false
        end
      else
        false
      end


    # An operator has clearance if they are an admin/moderator,
    # OR if they are explicitly whitelisted by the physical node owner or Mnesia table.
    is_authorized? =
      user &&
        (user.badge_type in ["admin", "root", "moderator", "staff"] or
           user.is_admin or
           user.is_moderator or
           is_node_owner? or
           is_whitelisted_node_operator?)

    if is_authorized? do
      # Inject transient sovereign keys into connection assigns map
      assign(conn, :is_sovereign_operator, true)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Sovereign Denied: Your signature is unauthorized on this hardware node."})
      |> halt()
    end
  end
end

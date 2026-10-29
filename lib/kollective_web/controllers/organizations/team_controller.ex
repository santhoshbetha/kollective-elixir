defmodule KollectiveWeb.TeamController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts

  plug KollectiveWeb.Plugs.RequireOrgAdmin when action in [:remove_member]

  @doc """
  Fetches and renders the active team roster for the current organization context.
  """
  # GET /api/v1/org-settings/members
  def index(conn, _params) do
    # Extracted securely by upstream org_context plug pipelines
    org_id = conn.assigns[:current_org_id]

    members = Accounts.list_active_members(org_id)

    conn
    |> put_view(KollectiveWeb.TeamJSON)
    |> render(:index, members: members)
  end

  @doc """
  Fetches outstanding, pending invitations sent out by this specific organization workspace.
  """
  # GET /api/v1/org-settings/pending-invites
  def pending_invites(conn, _params) do
    # Populated securely by your upstream org_context plug pipelines
    org_id = conn.assigns.current_org_id

    invites = Accounts.list_pending_org_invites(org_id)

    # Reuse or delegate to TeamJSON formatting layer
    conn
    |> put_view(KollectiveWeb.TeamJSON)
    |> render(:pending_invites, invites: invites)
  end

  # POST /api/v1/org-settings/members/:user_id/remove
  def remove_member(conn, params) do
    org_id = conn.assigns[:current_org_id] || params["org_id"]
    target_user_id = params["user_id"]

    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    actor_id = current_user && current_user.id

    case Accounts.remove_member(org_id, target_user_id, actor_id) do
      {:ok, %{audit_logging: audit_log}} ->
        audit_log = Kollective.Repo.preload(audit_log, [:actor])
        # 1. Broadcast live update to other active admins remaining on the page
        rendered_log = KollectiveWeb.AuditLogJSON.data(audit_log)

        KollectiveWeb.Endpoint.broadcast!(
          "org_admin_audit:#{org_id}",
          "new_audit_log",
          rendered_log
        )

        # 2. Force terminate the disconnected contributor's global WebSocket channel instantly
        KollectiveWeb.Endpoint.broadcast!(
          "users_socket:#{target_user_id}",
          "disconnect",
          %{}
        )

        send_resp(conn, :no_content, "")

      {:error, :cannot_remove_owner} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "You must transfer brand ownership before removing this profile."})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Member not found."})
    end
  end
end

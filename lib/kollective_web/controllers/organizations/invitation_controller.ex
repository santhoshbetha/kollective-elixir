defmodule KollectiveWeb.InvitationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.InvitationJSON

  # GET /api/v1/invitations
  def index(conn, _params) do
    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    user_id = current_user && current_user.id
    invitations = Accounts.list_pending_invitations(user_id)

    conn
    |> put_status(:ok)
    |> json(InvitationJSON.index(invitations))
  end

  # POST /api/invitations/:id/accept
  def accept(conn, %{"id" => id}) do
    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    user_id = current_user && current_user.id

    case Accounts.accept_invitation(user_id, id) do
      {:ok, membership} ->
        conn
        |> put_status(:ok)
        |> json(InvitationJSON.show(membership))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error:
            "This invitation link has expired or is no longer valid. Please ask an administrator to send a new invite."
        })
    end
  end

  # POST /api/invitations/:id/decline
  def decline(conn, %{"id" => id}) do
    current_user =
      conn.assigns[:current_user] ||
        (conn.assigns[:current_scope] && conn.assigns.current_scope.user)

    user_id = current_user && current_user.id

    case Accounts.decline_invitation(user_id, id) do
      {:ok, membership} ->
        conn
        |> put_status(:ok)
        |> json(InvitationJSON.show(membership))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invitation not found or already processed."})
    end
  end
end

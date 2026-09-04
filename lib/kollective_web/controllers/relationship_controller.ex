# lib/kollective_web/controllers/relationship_controller.ex
defmodule KollectiveWeb.RelationshipController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Users

  # ─── ACTION 1: LIST ACTIVE SYSTEM BLOCKS / MUTES (SETTINGS VIEWPORTS) ───
  # GET /api/v1/relationships
  # Expected params: ?type=block or ?type=mute
  def index(conn, %{"type" => type}) when type in ["block", "mute"] do
    user = conn.assigns.current_user

    # 1. Fetch matching user profile entities in exactly one query pass
    flagged_users = Users.list_related_users(user.id, type)

    conn
    |> put_status(:ok)
    # 2. Phoenix 1.7 approach: Format via your unified AccountJSON module contract
    |> json(%{
      status: "success",
      data:
        KollectiveWeb.AccountJSON.index(%{
          users: flagged_users,
          for: user,
          embed_relationships: true
        })
    })
  end

  def index(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Invalid relationship listing type."})

  # ─── ACTION 2: UNIVERSAL SOCIAL GRAPH TOGGLE LINK SWITCHER ───
  # POST /api/v1/relationships/toggle
  # Expected payload: %{"target_id" => "01J0A...", "type" => "follow" | "block" | "mute"}
  def toggle(conn, %{"target_id" => target_id, "type" => type})
      when type in ["follow", "block", "mute"] do
    user = conn.assigns.current_user

    # Prevent users from triggering self-referencing social graph operations
    if user.id == target_id do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Self-referencing actions are blocked."})
    else
      # Routes directly through your unified atomic Ecto.Multi context wrappers
      case Users.toggle_relationship(user, target_id, type) do
        {:ok, :created} ->
          json(conn, %{
            status: "success",
            action: "inserted",
            relationship_state: type,
            message: "Action successfully recorded."
          })

        {:ok, :deleted} ->
          json(conn, %{
            status: "success",
            action: "removed",
            relationship_state: "none",
            message: "Action successfully cleared."
          })

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Transaction failed to map parameters."})
      end
    end
  end

  def toggle(conn, _),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Prohibited configuration signature."})
end

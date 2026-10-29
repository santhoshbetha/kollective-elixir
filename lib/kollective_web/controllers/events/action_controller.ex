defmodule KollectiveWeb.ActionController do
  use KollectiveWeb, :controller
  import Ecto.Query

  alias Kollective.Events.Events
  alias Kollective.Events.Participant, as: EventParticipant
  alias Kollective.Repo
  alias KollectiveWeb.{ChangesetJSON, EventJSON}
  alias KollectiveWeb.Plugs.AuthorizeOrgSocialAction

  plug AuthorizeOrgSocialAction when action in [:rsvp, :attend]

  # GET /api/v1/actions (Feeds your "Organize Action" Dashboard Grid)
  # Supported params filter tab selections: ?category=protest&scope=local
  def index(conn, params) do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns[:current_user]
      end

    category_tab = Map.get(params, "category", "all")
    # "local", "state", "country", or "all"
    scope_toggle = Map.get(params, "scope", "all")

    # High-speed index driven lookup loop filters categories natively
    actions = Events.list_collective_actions(actor, category_tab, scope_toggle)
    hydrated_actions = attach_user_action_states(actions, actor)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: EventJSON.actions(hydrated_actions)
    })
  end

  # GET /api/v1/actions/:id (Individual organize action details)
  def show(conn, %{"id" => id}) do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns[:current_user]
      end

    case Events.get_event(id) do
      {:ok, action} ->
        [hydrated] = attach_user_action_states([action], actor)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: EventJSON.action_data(hydrated)
        })

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Action not found."})
    end
  end

  # POST /api/v1/actions (Step 2 "Launch Action" Wizard Terminal Trigger)
  def create(conn, params) do
    current_user = conn.assigns.current_user
    action_params = params["action"] || params["event"] || params

    case Events.create_action(current_user, action_params) do
      {:ok, action} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Grassroots action successfully initiated onto local perimeters.",
          data: EventJSON.action_data(action)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # POST /api/v1/actions/:id/rsvp or POST /api/v1/actions/:event_id/rsvp
  def rsvp(conn, params) do
    actor =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization]
      else
        conn.assigns.current_user
      end

    action_id = params["id"] || params["event_id"] || params["action_id"]
    status = Map.get(params, "status", "interested")

    case Events.rsvp_to_event(actor, action_id, status) do
        {:ok, code} when code in [:removed, "removed"] ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            code: "removed",
            isInterested: false,
            isAttending: false,
            rsvp: "None",
            user_rsvp_status: "None",
            userStatus: "None",
            message: "RSVP removed."
          })

        {:ok, final_code} ->
          code_str = to_string(final_code) |> String.downcase()
          is_interested = code_str == "interested"
          is_attending = code_str in ["accepted", "joined", "going", "attending"]

          rsvp_status =
            cond do
              is_attending -> "Attending"
              is_interested -> "Interested"
              true -> "None"
            end

          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            code: code_str,
            isInterested: is_interested,
            isAttending: is_attending,
            rsvp: rsvp_status,
            user_rsvp_status: rsvp_status,
            userStatus: rsvp_status,
            message: "RSVP updated to: #{status}"
          })

        {:error, "Conflict:" <> _ = conflict_msg} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "calendar_conflict", message: conflict_msg})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "rsvp_failed", message: to_string(reason)})
      end
  end

  # POST /api/v1/actions/:id/attend
  def attend(conn, params) do
    rsvp(conn, Map.put(params, "status", "attending"))
  end

  defp attach_user_action_states(actions, nil), do: actions

  defp attach_user_action_states(actions, user) do
    action_ids = Enum.map(actions, & &1.id)

    user_rsvps =
      if action_ids != [] do
        from(p in EventParticipant,
          where: p.user_id == ^user.id and p.event_id in ^action_ids,
          select: {p.event_id, p.status}
        )
        |> Repo.all()
        |> Enum.into(%{})
      else
        %{}
      end

    Enum.map(actions, fn action ->
      join_state =
        case Map.get(user_rsvps, action.id) do
          s when s in ["accepted", "going", "attending", "joined"] -> "Attending"
          s when s in ["interested", "maybe"] -> "Interested"
          _ -> "None"
        end

      Map.put(action, :join_state, join_state)
    end)
  end
end

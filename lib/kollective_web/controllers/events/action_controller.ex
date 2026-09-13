defmodule KollectiveWeb.ActionController do
  use KollectiveWeb, :controller
  alias Kollective.Events.Events
  alias KollectiveWeb.{ChangesetJSON, EventJSON}

  # GET /api/v1/actions (Feeds your "Organize Action" Dashboard Grid)
  # Supported params filter tab selections: ?category=protest&scope=local
  def index(conn, params) do
    user = conn.assigns.current_user
    category_tab = Map.get(params, "category", "all")
    # "local", "state", "country"
    scope_toggle = Map.get(params, "scope", "local")

    # High-speed index driven lookup loop filters categories natively
    actions = Events.list_collective_actions(user, category_tab, scope_toggle)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: EventJSON.actions(actions)
    })
  end

  # POST /api/v1/actions (Step 2 "Launch Action" Wizard Terminal Trigger)
  def create(conn, %{"event" => action_params}) do
    current_user = conn.assigns.current_user

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
end

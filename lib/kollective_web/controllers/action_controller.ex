# lib/kollective_web/controllers/action_controller.ex
defmodule KollectiveWeb.ActionController do
  use KollectiveWeb, :controller
  alias Kollective.Events.Events

  # GET /api/v1/actions (Feeds your "Organize Action" Dashboard Grid)
  # Supported params filter tab selections: ?category=protest&scope=local
  def index(conn, params) do
    user = conn.assigns.current_user
    category_tab = Map.get(params, "category", "all")
    # "local", "state", "country"
    scope_toggle = Map.get(params, "scope", "local")

    # High-speed index driven lookup loop filters categories natively
    actions = Events.list_collective_actions(user, category_tab, scope_toggle)

    json(conn, %{
      status: "success",
      data:
        Enum.map(actions, fn item ->
          %{
            id: to_string(item.id),
            name: item.name,
            description: item.description,
            category: item.category,
            participation_format: item.participation_format,
            start_time: Calendar.strftime(item.start_time, "%Y-%m-%dT%H:%M:%SZ"),
            location_name: item.location_name,
            participants_count: item.participants_count,
            # Renders the "OFFICIAL" badge in React
            is_official: not is_nil(item.organization_id),
            initiator: item.user.username
          }
        end)
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
          data: %{id: to_string(action.id), name: action.name, category: action.category}
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end
end

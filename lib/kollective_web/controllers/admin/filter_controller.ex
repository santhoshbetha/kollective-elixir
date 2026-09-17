# lib/kollective_web/controllers/filter_controller.ex
defmodule KollectiveWeb.FilterController do
  use KollectiveWeb, :controller

  alias Kollective.Posts.UserFilter
  alias Kollective.Repo

  # GET /api/v1/filters
  def index(conn, _params) do
    user = conn.assigns.current_user
    filters = UserFilter.list_active_filters(user)

    json(conn, %{status: "success", data: KollectiveWeb.FilterJSON.index(%{filters: filters})})
  end

  # POST /api/v1/filters
  def create(conn, %{"filter" => filter_params}) do
    user = conn.assigns.current_user

    attrs = Map.put(filter_params, "user_id", user.id)

    %UserFilter{}
    |> UserFilter.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, filter} ->
        conn
        |> put_status(:created)
        |> json(%{status: "success", data: KollectiveWeb.FilterJSON.show(%{filter: filter})})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
    end
  end

  # DELETE /api/v1/filters/:id
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case UserFilter.get_user_filter(id, user) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "Filter parameter not found."})

      filter ->
        Repo.delete!(filter)
        json(conn, %{status: "success", message: "Mute phrase successfully removed."})
    end
  end

  def delete_filter(conn, params), do: delete(conn, params)
end

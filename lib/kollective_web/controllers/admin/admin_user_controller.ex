defmodule KollectiveWeb.AdminUserController do
  use KollectiveWeb, :controller
  import Ecto.Query
  alias Kollective.{Repo, Accounts.User}

  # GET /api/admin/users/search?q=voter123
  def search(conn, %{"q" => query}) do
    search_term = "%#{query}%"

    users =
      User
      |> where([u], ilike(u.username, ^search_term) or ilike(u.email, ^search_term))
      |> limit(5)
      |> Repo.all()
      |> Repo.preload([:district_l1, :district_l2, :district_l3, :city])

    render(conn, :index, users: users)
  end

  # PUT /api/admin/users/:id/override-districts
  def override_districts(conn, %{"id" => id, "override" => params}) do
    user = Repo.get!(User, id)

    # Use the existing changeset directly—since admins supply all 3 fields,
    # our complete political stack validation guard passes perfectly!
    changeset =
      User.registration_changeset(user, %{
        district_l1_id: params["district_l1_id"],
        district_l2_id: params["district_l2_id"],
        district_l3_id: params["district_l3_id"],
        origin_city_id: params["origin_city_id"]
      })

    case Repo.update(changeset) do
      {:ok, updated_user} ->
        json(conn, %{status: "success", user_id: updated_user.id})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: KollectiveWeb.ChangesetJSON)
        |> render(:error, changeset: changeset)
    end
  end
end

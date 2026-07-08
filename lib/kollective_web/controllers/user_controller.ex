# lib/kollective_web/controllers/user_controller.ex
defmodule KollectiveWeb.UserController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Users
  alias Kollective.External.CivicService

  # GET /api/me
  def me(conn, _params) do
    user = conn.assigns.current_user

    # Preload the 3 political tiers for the JSON view
    user = Users.load_user_districts(user)

    render(conn, :show, user: user)
  end

  # When the user clicks a tab (e.g., switching from "State" to "Local"), the React app hits an
  # endpoint to clear the badge for that specific user.
  def clear_feed_badge(conn, _params) do
    user = conn.assigns.current_user

    case Users.mark_feed_as_read(user) do
      {:ok, _user} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(400) |> json(%{error: "failed"})
    end
  end

  @doc """
  PATCH /api/v1/profile/districts
  Accepts a raw text address payload string, uses the external Google Civic API
  to resolve official local boundary data, and applies updates to the user row .
  """
  def update_districts(conn, %{"address" => address}) do
    # 1. Fetch the user profile struct straight out of RAM memory
    user = conn.assigns.current_user

    # 2. Fire the external lookup to extract political perimeters
    case CivicService.find_districts_by_address(address) do
      {:ok, civic_data} ->
        # Remap parsed key attributes to match your flat standalone user schema columns
        district_params = %{
          "origin_state" => civic_data.state,
          "district_l1" => civic_data.federal_district,
          "district_l2" => civic_data.state_senate_district,
          "district_l3" => civic_data.state_district
        }

        # 3. Write the resolved perimeters into the database row
        case Users.update_user_districts(user, district_params) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            # Modern Warning-Free Alternative: Serialize directly to json/2
            |> json(%{
              status: "success",
              message: "Political boundaries successfully synchronized.",
              data: KollectiveWeb.AccountJSON.show(%{user: updated_user, for: updated_user})
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(KollectiveWeb.ChangesetJSON.error(%{changeset: changeset}))
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: "boundary_resolution_failed", message: reason})
    end
  end

  def update_districts(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Missing address parameter."})
end

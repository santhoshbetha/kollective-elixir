defmodule KollectiveWeb.CivicController do
  use KollectiveWeb, :controller
  alias Kollective.Services.GeocodioClient
  alias Kollective.Accounts.Users

  def update_precinct_node(conn, %{"address" => address}) do
    user = conn.assigns.current_user

    case GeocodioClient.fetch_civic_data(address) do
      {:ok, civic_data} ->
        # Persist extracted election codes directly onto the current user record
        {:ok, updated_user} = Users.update_user_political_bounds(user, civic_data)
        render(conn, "user.json", user: updated_user)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
end

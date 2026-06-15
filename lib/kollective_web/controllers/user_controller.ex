# lib/kollective_web/controllers/user_controller.ex
defmodule KollectiveWeb.UserController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Users

  # GET /api/me
  def me(conn, _params) do
    user = conn.assigns.current_user

    # Preload the 3 political tiers for the JSON view
    user = Users.load_user_districts(user)

    render(conn, :show, user: user)
  end

  #When the user clicks a tab (e.g., switching from "State" to "Local"), the React app hits an
  # endpoint to clear the badge for that specific user.
  def clear_feed_badge(conn, _params) do
    user = conn.assigns.current_user

    case Users.mark_feed_as_read(user) do
      {:ok, _user} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(400) |> json(%{error: "failed"})
    end
  end
end

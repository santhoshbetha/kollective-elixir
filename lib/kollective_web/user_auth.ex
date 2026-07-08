defmodule KollectiveWeb.UserAuth do
  use KollectiveWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Kollective.Accounts.Scope

  @doc """
  Assigns the domain structural scope metadata onto the connection mapping.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        assign(conn, :current_scope, Scope.for_user(nil))

      user ->
        assign(conn, :current_scope, Scope.for_user(user))
    end
  end

  @doc """
  Plug for routes that require sudo mode (recent re-authentication window).
  """
  def require_sudo_mode(conn, _opts) do
    # 💡 Fetch the user struct safely out of the newly generated scope profile
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "You must log in to access this resource."})
        |> halt()

      # Check if authentication happened inside the safe 10-minute window
      is_nil(user.authenticated_at) or
          DateTime.compare(user.authenticated_at, DateTime.add(DateTime.utc_now(), -10, :minute)) ==
            :lt ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You must re-authenticate to access this resource."})
        |> halt()

      true ->
        conn
    end
  end

  @doc """
  Plug for routes that require the user to not be authenticated (Guest Zone).
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    # 💡 Sync to evaluate against the newly fetched scope mapping matrix
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You are already logged in."})
      |> halt()
    else
      conn
    end
  end

  @doc """
  Plug for routes that require the user to be authenticated (Protected Zone).
  """
  def require_authenticated_user(conn, _opts) do
    # safe map checks prevent dot notation crashes
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{status: "error", message: "You must log in to access this resource."})
      |> halt()
    end
  end
end

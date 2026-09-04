# lib/kollective_web/plugs/admin_auth.ex
defmodule KollectiveWeb.Plugs.AdminAuth do
  import Plug.Conn
  import Phoenix.Controller

  @doc """
  Halts the connection pipeline instantly if the token-authenticated
  current_user context does not bear explicit administrative privileges.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %Kollective.Accounts.User{role: :admin} ->
        # Access granted. Proceed downstream safely.
        conn

      _any_other_user ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access Denied: Administrative privileges are strictly required."})
        |> halt()
    end
  end
end

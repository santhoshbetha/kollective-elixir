defmodule KollectiveWeb.Plugs.RequireOrgAdmin do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:org_role] in [:admin, :owner] do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "You must be an admin or owner of this organization to perform this action."
      })
      |> halt()
    end
  end
end

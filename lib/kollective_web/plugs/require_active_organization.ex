defmodule KollectiveWeb.Plugs.RequireActiveOrganization do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    # Check if the previous plug successfully extracted an active organization ID
    if conn.assigns[:current_org_id] do
      # All good, pass through to the next plug/controller
      conn
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        error:
          "This action requires an active organization context. Please provide a valid X-Organization-Id header."
      })
      # Stop the request execution chain immediately
      |> halt()
    end
  end
end

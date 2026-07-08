defmodule KollectiveWeb.Plugs.RequireAdminAuthenticated do
  @moduledoc """
  High-Performance Administrative Access Enforcement Guard.
  Inspects the pre-loaded current_user struct assigned in RAM and blocks
  non-privileged users immediately at the gateway before routing to controllers.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    # Enforce strict compliance checks against your core identity privilege flags
    if user && (user.is_admin || user.is_moderator) do
      # Authorized: Allow the connection to pass forward cleanly
      conn
    else
      # 1. Compile the payload map natively
      response_payload = %{
        status: "error",
        code: "unauthorized_access",
        message:
          "You do not have the necessary administrative privileges to access this resource."
      }

      # 2. Encode to a JSON string in RAM and halt the request instantly
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(response_payload))
      |> halt()
    end
  end
end

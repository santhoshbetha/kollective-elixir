defmodule KollectiveWeb.HealthController do
  @moduledoc "Minimal health endpoint used by the E2E runner and uptime checks."
  use KollectiveWeb, :controller

  def show(conn, _params) do
    IO.inspect(
      "Health check hit on port #{Application.get_env(:kollective, KollectiveWeb.Endpoint)[:http][:port]}!"
    )

    json(conn, %{status: "ok"})
  end
end

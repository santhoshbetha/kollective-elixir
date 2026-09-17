defmodule KollectiveWeb.Plugs.CORS do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    origin =
      case get_req_header(conn, "origin") do
        [h | _] -> h
        [] -> "*"
      end

    req_headers =
      case get_req_header(conn, "access-control-request-headers") do
        [h | _] when h != "" ->
          h

        _ ->
          "authorization, content-type, x-active-account-id, accept, origin, user-agent, x-requested-with"
      end

    conn =
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
      |> put_resp_header("access-control-allow-headers", req_headers)
      |> put_resp_header("access-control-allow-credentials", "true")
      |> put_resp_header("access-control-max-age", "86400")

    if conn.method == "OPTIONS" do
      conn
      |> send_resp(204, "")
      |> halt()
    else
      conn
    end
  end
end

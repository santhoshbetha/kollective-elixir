defmodule KollectiveWeb.OptionsController do
  use KollectiveWeb, :controller

  def options(conn, _params) do
    send_resp(conn, 204, "")
  end
end

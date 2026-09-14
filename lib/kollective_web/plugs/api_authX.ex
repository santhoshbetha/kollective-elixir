defmodule KollectiveWeb.Plugs.APIAuthX do
  import Plug.Conn
  import Phoenix.Controller

  alias Kollective.Accounts.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method == "OPTIONS" do
      conn
    else
      authenticate_token(conn)
    end
  end

  defp authenticate_token(conn) do
    with ["Bearer " <> encoded_token] <- get_req_header(conn, "authorization"),
         {:ok, raw_token_bytes} <- Base.url_decode64(encoded_token, padding: false),
         # 💡 Unpacks the database tuple cleanly from the binary token lookup
         {user, _inserted_at} when not is_nil(user) <-
           Accounts.get_user_by_session_token(raw_token_bytes) do
      assign(conn, :current_user, user)
    else
      _any ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized", message: "You must log in to access this resource"})
        |> halt()
    end
  end
end

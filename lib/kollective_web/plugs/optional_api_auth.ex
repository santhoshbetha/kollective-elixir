defmodule KollectiveWeb.Plugs.OptionalAPIAuth do
  import Plug.Conn
  alias Kollective.Accounts.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method == "OPTIONS" do
      conn
    else
      conn
      |> authenticate_optional_user()
    end
  end

  defp authenticate_optional_user(conn) do
    if conn.assigns[:current_user] do
      conn
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> encoded_token] ->
          with {:ok, raw_token_bytes} <- decode_token(encoded_token),
               {user, _inserted_at} when not is_nil(user) <- Accounts.get_user_by_session_token(raw_token_bytes) do
            assign(conn, :current_user, user)
          else
            _ ->
              assign(conn, :current_user, nil)
          end

        _ ->
          assign(conn, :current_user, nil)
      end
    end
  end

  defp decode_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      :error ->
        case Base.url_decode64(token) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> Base.decode64(token)
        end
    end
  end
end

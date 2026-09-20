defmodule KollectiveWeb.Plugs.APIAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.Organizations
  alias Kollective.Accounts.OrganizationMembership

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method == "OPTIONS" do
      conn
    else
      conn
      |> authenticate_user()
      # 🧠 This handles the switching!
      |> resolve_account_context()
    end
  end

  # 1. Authenticate the underlying user account
  defp authenticate_user(conn) do
    if conn.assigns[:current_user] do
      conn
    else
      with ["Bearer " <> encoded_token] <- get_req_header(conn, "authorization"),
           {:ok, raw_token_bytes} <- decode_token(encoded_token),
           {user, _inserted_at} when not is_nil(user) <-
             Accounts.get_user_by_session_token(raw_token_bytes) do
        assign(conn, :current_user, user)
      else
        _any ->
          unauthorized_response(conn)
      end
    end
  end

  defp decode_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bytes} ->
        {:ok, bytes}

      :error ->
        case Base.url_decode64(token) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> Base.decode64(token)
        end
    end
  end

  # 2. Scope permissions based on the frontend's requested Active Account
  defp resolve_account_context(%{halted: true} = conn), do: conn

  defp resolve_account_context(conn) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      unauthorized_response(conn)
    else
      # React will send this header on every request (fallback to user's personal ID if missing)
      active_account_id =
        case get_req_header(conn, "x-active-account-id") do
          [id] when id not in ["", "null", "undefined"] -> id
          _empty -> to_string(user.id)
        end

      cond do
        # Case A: User is operating under their own personal account (or mock personal ID / non-ULID)
        to_string(user.id) == to_string(active_account_id) or
          active_account_id in ["personal", "usr-1"] or
          String.starts_with?(to_string(active_account_id), "usr-") or
          match?(:error, Ecto.ULID.cast(active_account_id)) ->
          personal_permissions = ["posts:write", "profile:manage"]

          conn
          |> assign(:active_account_id, to_string(user.id))
          |> assign(:account_type, user.type)
          |> assign(:permissions, personal_permissions)

        # Case B: User is operating under an Organization account
        true ->
          case Accounts.get_active_membership(user.id, active_account_id) do
            %OrganizationMembership{organization: org, role: role} when not is_nil(org) ->
              permissions = Organizations.permissions_for_role(role)

              conn
              |> assign(:active_account_id, to_string(org.id))
              |> assign(:account_type, org.type)
              |> assign(:permissions, permissions)

            _ ->
              # Case C: Rogue header or unauthorized access
              conn
              |> put_status(:forbidden)
              |> json(%{
                error: "forbidden",
                message: "You do not have access to this account profile."
              })
              |> halt()
          end
      end
    end
  end

  defp unauthorized_response(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized", message: "You must log in to access this resource"})
    |> halt()
  end
end

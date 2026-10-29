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
           {user, _inserted_at, context} when not is_nil(user) <-
             Accounts.get_user_and_context_by_session_token(raw_token_bytes) do
        conn
        |> assign(:current_user, user)
        |> assign(:session_token_context, context)
      else
        _any ->
          with ["Bearer " <> encoded_token] <- get_req_header(conn, "authorization"),
               {:ok, raw_token_bytes} <- decode_token(encoded_token),
               {user, _inserted_at} when not is_nil(user) <-
                 Accounts.get_user_by_session_token(raw_token_bytes) do
            conn
            |> assign(:current_user, user)
            |> assign(:session_token_context, "session")
          else
            _ ->
              unauthorized_response(conn)
          end
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
      token_context = conn.assigns[:session_token_context]

      token_org_id =
        case token_context do
          "session:org:" <> org_id when byte_size(org_id) > 0 -> org_id
          _ -> nil
        end

      active_account_id =
        cond do
          not is_nil(token_org_id) ->
            token_org_id

          true ->
            case get_req_header(conn, "x-active-account-id") do
              [id] when id not in ["", "null", "undefined"] -> id
              _empty -> to_string(user.id)
            end
        end

      cond do
        # Case A: User is operating under their own personal account (or mock personal ID / non-ULID)
        to_string(user.id) == to_string(active_account_id) or
          active_account_id in ["personal", "usr-1"] or
          String.starts_with?(to_string(active_account_id), "usr-") or
          (is_nil(token_org_id) and match?(:error, Ecto.ULID.cast(active_account_id))) ->
          personal_permissions = ["posts:write", "profile:manage"]

          conn
          |> assign(:current_organization, nil)
          |> assign(:current_org_id, nil)
          |> assign(:org_role, nil)
          |> assign(:active_account_id, to_string(user.id))
          |> assign(:account_type, user.type)
          |> assign(:permissions, personal_permissions)

        # Case B: User is operating under an Organization account
        true ->
          case Accounts.get_active_membership(user.id, active_account_id) do
            %OrganizationMembership{organization: org, role: role} when not is_nil(org) ->
              permissions = Organizations.permissions_for_role(role)

              conn
              |> assign(:current_organization, org)
              |> assign(:current_org_id, to_string(org.id))
              |> assign(:org_role, role)
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

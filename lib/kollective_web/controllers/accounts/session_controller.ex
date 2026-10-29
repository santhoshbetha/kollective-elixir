defmodule KollectiveWeb.SessionController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.AccountJSON

  # ─── ACTION 1: EMAIL / USERNAME + PASSWORD LOGIN ───
  def create(conn, %{
        "action" => "password",
        "user" => %{"email" => email, "password" => password}
      }) do
    do_password_login(conn, email, password)
  end

  def create(conn, %{
        "action" => "password",
        "user" => %{"login" => login, "password" => password}
      }) do
    do_password_login(conn, login, password)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    do_password_login(conn, email, password)
  end

  def create(conn, %{"user" => %{"login" => login, "password" => password}}) do
    do_password_login(conn, login, password)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    do_password_login(conn, email, password)
  end

  def create(conn, %{"login" => login, "password" => password}) do
    do_password_login(conn, login, password)
  end

  def create(conn, %{"username" => username, "password" => password}) do
    do_password_login(conn, username, password)
  end

  # ─── ACTION 2: MAGIC LINK VERIFICATION ───
  def create(conn, %{"action" => "verify_magic_link", "user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {:ok, {user, _expired_tokens}}} ->
        token = Accounts.generate_user_session_token(user)
        profiles = Accounts.list_user_profiles(user)

        conn
        |> put_status(:ok)
        |> json(%{
          token: token,
          user: AccountJSON.profile_data(user),
          message: "Welcome back!",
          profiles: profiles,
          data: %{token: token, user: AccountJSON.profile_data(user), profiles: profiles}
        })

      {:ok, {user, _expired_tokens}} ->
        token = Accounts.generate_user_session_token(user)
        profiles = Accounts.list_user_profiles(user)

        conn
        |> put_status(:ok)
        |> json(%{
          token: token,
          user: AccountJSON.profile_data(user),
          message: "Welcome back!",
          profiles: profiles,
          data: %{token: token, user: AccountJSON.profile_data(user), profiles: profiles}
        })

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "The link is invalid or it has expired."})
    end
  end

  # ─── ACTION 3: MAGIC LINK REQUEST ───
  def create(conn, %{"action" => "request_magic_link", "user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &"https://kollective.social#{&1}"
      )
    end

    conn
    |> put_status(:accepted)
    |> json(%{
      message: "If your email is in our system, you will receive instructions shortly."
    })
  end

  # ─── FALLBACK CLAUSE FOR INVALID PAYLOADS ───
  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid login credentials parameters."})
  end

  # ─── LOGOUT MUTATION ───
  def delete(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization") do
      case Accounts.get_user_by_session_token(token) do
        {user, _inserted_at} ->
          Accounts.revoke_user_session_tokens(user)

        _ ->
          Accounts.delete_user_session_token(token)
      end

      conn
      |> put_status(:ok)
      |> json(%{message: "Logged out successfully."})
    else
      _missing_header ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing authorization bearer token."})
    end
  end

  # ─── PRIVATE HELPERS ───
  defp do_password_login(conn, identifier, password)
       when is_binary(identifier) and is_binary(password) do
    user =
      Accounts.get_user_by_email_and_password(identifier, password) ||
        get_user_by_username_and_password(identifier, password)

    if user do
      token = Accounts.generate_user_session_token(user)
      profiles = Accounts.list_user_profiles(user)

      conn
      |> put_status(:ok)
      |> json(%{
        token: token,
        user: AccountJSON.profile_data(user),
        message: "Welcome back!",
        profiles: profiles,
        data: %{token: token, user: AccountJSON.profile_data(user), profiles: profiles}
      })
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Invalid email or password"})
    end
  end

  defp do_password_login(conn, _identifier, _password) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email/username and password must be strings."})
  end

  defp get_user_by_username_and_password(username, password) do
    user = Kollective.Repo.get_by(Kollective.Accounts.User, username: username)
    if user && Kollective.Accounts.User.valid_password?(user, password), do: user
  end

  # ─── ACTION 4: SWITCH ORGANIZATION / PERSONAL PROFILE ───
  def switch_profile(conn, params) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized", message: "You must be logged in to switch profiles."})
    else
      target_id = params["organization_id"] || params["profile_id"]

      cond do
        # Case 1: Switching back to personal profile
        is_nil(target_id) or target_id in ["", "personal", "personal_account"] or
            to_string(target_id) == to_string(user.id) ->
          Accounts.revoke_user_session_tokens(user)
          token = Accounts.generate_user_session_token(user)
          user_data = AccountJSON.login_profile(user)

          active_account = %{
            id: to_string(user.id),
            type: "personal",
            name: user_data.display_name || user.username,
            username: user.username,
            handle: "@#{user.username}",
            avatar: user_data.avatar,
            role: to_string(user.role || :citizen)
          }

          conn
          |> put_status(:ok)
          |> json(%{
            token: token,
            user: user_data,
            active_account: active_account,
            message: "Profile switched to personal successfully."
          })

        # Case 2: Switching to organization profile
        true ->
          case Accounts.get_active_membership(user.id, target_id) do
            nil ->
              conn
              |> put_status(:forbidden)
              |> json(%{
                error: "forbidden",
                message: "You do not have access to this organization profile."
              })

            %Kollective.Accounts.OrganizationMembership{organization: org, role: role} ->
              Accounts.revoke_user_session_tokens(user)
              token = Accounts.generate_organization_session_token(user, org.id)

              org_data = AccountJSON.login_profile(org)
              user_data = AccountJSON.login_profile(user)

              active_account = %{
                id: to_string(org.id),
                type: "organization",
                name: org_data.display_name || org.username,
                username: org.username,
                handle: "@#{org.username}",
                avatar: org_data.avatar,
                role: to_string(role)
              }

              conn
              |> put_status(:ok)
              |> json(%{
                token: token,
                user: user_data,
                organization: org_data,
                active_account: active_account,
                message: "Profile switched successfully."
              })
          end
      end
    end
  end
end

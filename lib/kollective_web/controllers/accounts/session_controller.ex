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
      Accounts.delete_user_session_token(token)

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
end

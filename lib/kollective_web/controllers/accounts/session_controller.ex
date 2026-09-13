defmodule KollectiveWeb.SessionController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias KollectiveWeb.AccountJSON

  # email + password login
  def create(conn, %{
        "action" => "password",
        "user" => %{"email" => email, "password" => password}
      }) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.generate_user_session_token(user)

      conn
      |> put_status(:ok)
      |> json(%{
        message: "Welcome back!",
        data: %{token: token, user: AccountJSON.profile_data(user)}
      })
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Invalid email or password"})
    end
  end

  # magic link login (Verifies token from email link)
  def create(conn, %{"action" => "verify_magic_link", "user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {:ok, {user, _expired_tokens}}} ->
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Welcome back!",
          data: %{token: token, user: AccountJSON.profile_data(user)}
        })

      {:ok, {user, _expired_tokens}} ->
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Welcome back!",
          data: %{token: token, user: AccountJSON.profile_data(user)}
        })

      # 🔄 FIX: Add a flexible pattern matcher to catch all verification/not_found errors
      # and return a clean 422 JSON payload to your React frontend.
      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "The link is invalid or it has expired."})
    end
  end

  # magic link request (Generates and emails link)
  def create(conn, %{"action" => "request_magic_link", "user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      # Note: Update your mailer template to link to your FRONTEND app URL, not Phoenix HTML
      Accounts.deliver_login_instructions(
        user,
        &"https://kollective.social#{&1}"
      )
    end

    # Return identical generic response to prevent user enumeration attacks
    conn
    # 202
    |> put_status(:accepted)
    |> json(%{
      message: "If your email is in our system, you will receive instructions shortly."
    })
  end

  def delete(conn, _params) do
    # Read the token directly from the request headers
    with ["Bearer " <> token] <- get_req_header(conn, "authorization") do
      # Deletes the active token row directly from your users_tokens database table
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
end

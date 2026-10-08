defmodule KollectiveWeb.ResetPasswordController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  # Intercept and validate the token before allowing a password update
  plug :get_user_by_reset_password_token when action in [:update]

  # 1. REQUEST PASSWORD RESET LINK (Sends Email)
  # POST /api/users/reset_password
  def create(conn, params) do
    email =
      get_in(params, ["user", "email"]) ||
        params["email"] ||
        ""

    if email != "" do
      Accounts.reset_password_for_email(email, fn token ->
        frontend_url = System.get_env("FRONTEND_URL") || "http://localhost:5173"
        "#{frontend_url}/reset_password?token=#{token}"
      end)
    end

    conn
    # Always return 200 OK to prevent malicious user enumeration attacks
    |> put_status(:ok)
    |> json(%{
      status: "success",
      message: "If this email is associated with an account, a password reset link has been sent."
    })
  end

  # 2. SUBMIT NEW PASSWORD (Fires update query)
  # PUT /api/users/reset_password/:token
  def update(conn, params) do
    user = conn.assigns.user

    user_params =
      get_in(params, ["user"]) ||
        %{
          "password" => params["password"],
          "password_confirmation" => params["password_confirmation"] || params["password_confirm"]
        }

    case Accounts.reset_user_password(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Password has been reset successfully"})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  # 3. HELPER PLUG: Token Verification Guard
  defp get_user_by_reset_password_token(conn, _opts) do
    token = conn.params["token"] || get_in(conn.params, ["user", "token"])

    case token && Accounts.get_user_by_reset_password_token(token) do
      %Kollective.Accounts.User{} = user ->
        conn
        |> assign(:user, user)
        |> assign(:token, token)

      _invalid_or_missing ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          status: "error",
          message: "The reset password token is invalid or has expired."
        })
        |> halt()
    end
  end
end

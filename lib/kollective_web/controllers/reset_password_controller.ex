defmodule KollectiveWeb.ResetPasswordController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  # Intercept and validate the token before allowing a password update
  plug :get_user_by_reset_password_token when action in [:update]

  # 1. REQUEST PASSWORD RESET LINK (Sends Email)
  def create(conn, %{"user" => %{"email" => email}}) do
    # Point this link explicitly to your separate FRONTEND application layout
    Accounts.reset_password_for_email(email, fn token ->
      "https://kollective.social/reset_password?token=#{token}"
    end)

    conn
    # Always return 200 OK to prevent malicious user enumeration attacks

    |> put_status(:ok)
    |> json(%{
      status: "success",
      message: "If this email is associated with an account, a password reset link has been sent."
    })
  end

  # 2. SUBMIT NEW PASSWORD (Fires update query)
  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.user

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
    # Pull token parameter safely whether it passes via body JSON or query string maps
    with %{"token" => token} <- conn.params,
         user when not is_nil(user) <- Accounts.get_user_by_reset_password_token(token) do
      conn
      |> assign(:user, user)
      |> assign(:token, token)
    else
      _invalid_or_missing ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          status: "error",
          message: "The reset password token is invalid or has expired."
        })
        # CRUCIAL: Blocks execution thread from jumping down into update/2
        |> halt()
    end
  end
end

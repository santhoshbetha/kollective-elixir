defmodule KollectiveWeb.SettingsController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  import KollectiveWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode
  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, :edit)
  end

  # 1. UPDATE EMAIL
  def update(conn, %{"action" => "update_email", "user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &"https://kollective99.com#{&1}"
        )

        conn
        |> put_status(:ok)
        |> json(%{
          message: "A link to confirm your email change has been sent to the new address."
        })

      changeset ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  # 2. UPDATE PASSWORD
  def update(conn, %{"action" => "update_password", "user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        # Generate a fresh API session token since credentials just changed
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Password updated successfully.",
          data: %{
            token: token,
            user: %{id: user.id, email: user.email}
          }
        })

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  # 3. CONFIRM EMAIL CHANGE (Invoked by clicking the email link)
  @spec confirm_email(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Email changed successfully.",
          data: %{
            user: %{id: user.id, email: user.email}
          }
        })

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Email change link is invalid or it has expired."})
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end

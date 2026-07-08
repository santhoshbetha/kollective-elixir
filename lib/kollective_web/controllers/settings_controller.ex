defmodule KollectiveWeb.SettingsController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  import KollectiveWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode
  plug :assign_email_and_password_changesets  when action in [:edit, :update]

  def edit(conn, _params) do
    user = conn.assigns.current_user

    # 🏆 Explicitly triggers the rendering pipeline template we created above
    render(conn, :edit, user: user)
  end

  # 1. UPDATE EMAIL
  def update(conn, %{"action" => "update_email", "user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &"https://kollective.social#{&1}"
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
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, user_params) do
      # 1. Catch a completely successful password change transaction
      {:ok, {:ok, {updated_user, _expired_tokens}}} ->
        token = Accounts.generate_user_session_token(updated_user)

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Password updated successfully.",
          data: %{
            token: token,
            user: %{id: updated_user.id, email: updated_user.email}
          }
        })

      # 🔄 FIX: Explicitly catch validation errors wrapped inside the transaction tuple
      {:ok, {:error, %Ecto.Changeset{} = changeset}} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})

      # Flat fallback success pattern match
      {:ok, updated_user} ->
        token = Accounts.generate_user_session_token(updated_user)

        conn
        |> put_status(:ok)
        |> json(%{
          message: "Password updated successfully.",
          data: %{
            token: token,
            user: %{id: updated_user.id, email: updated_user.email}
          }
        })

      # Standard flat error fallback match
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
    case Accounts.update_user_email(conn.assigns.current_user, token) do
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

  # defp assign_email_and_password_changesetsX(conn, _opts) do
  #   user = conn.assigns.current_scope.user
  #
  #   conn
  #   |> assign(:email_changeset, Accounts.change_user_email(user))
  #   |> assign(:password_changeset, Accounts.change_user_password(user))
  # end

  defp assign_email_and_password_changesets(conn, _opts) do
    # 🔄 FIX: Fetch from :current_user instead of the old :current_scope structure
    user = conn.assigns.current_user

    # Keep your existing changeset generation logic exactly as-is:
    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end

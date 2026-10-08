defmodule KollectiveWeb.SettingsController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User
  alias Kollective.Repo

  plug :assign_email_and_password_changesets when action in [:edit, :update]

  @doc """
  POST /api/v1/settings/change_email
  Updates the user's primary contact email address after verifying their current password.
  """
  def change_email(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    email = params["email"] || get_in(params, ["user", "email"])
    password = params["password"] || params["current_password"] || get_in(params, ["user", "password"])

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required."})

      is_nil(password) or password == "" ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Current password is required to change email."})

      not User.valid_password?(user, password) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid current password."})

      is_nil(email) or String.trim(email) == "" ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "New email address is required."})

      true ->
        email = String.trim(email)
        changeset = User.email_changeset(user, %{"email" => email})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Email address updated successfully.",
              data: %{
                user: %{
                  id: updated_user.id,
                  email: updated_user.email,
                  username: updated_user.username,
                  display_name: updated_user.display_name,
                  avatar: updated_user.avatar
                }
              }
            })

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            error_msg =
              cond do
                errors[:email] -> "Email " <> Enum.join(errors[:email], ", ")
                true -> "Failed to update email address."
              end

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: error_msg, errors: errors})
        end
    end
  end

  @doc """
  POST /api/v1/settings/change_password
  Updates the user's password after verifying their current password.
  """
  def change_password(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    current_password = params["current_password"] || params["password"] || get_in(params, ["user", "current_password"])
    new_password = params["new_password"] || params["password_confirmation"] || get_in(params, ["user", "new_password"])

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required."})

      is_nil(current_password) or current_password == "" ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Current password is required."})

      not User.valid_password?(user, current_password) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid current password."})

      is_nil(new_password) or String.length(new_password) < 8 ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "New password must be at least 8 characters long."})

      true ->
        changeset = User.password_changeset(user, %{"password" => new_password, "password_confirmation" => new_password})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Password updated successfully.",
              data: %{
                user: %{
                  id: updated_user.id,
                  email: updated_user.email
                }
              }
            })

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update password.", errors: errors})
        end
    end
  end

  @doc """
  DELETE /api/v1/settings/delete_account
  Permanently deletes the user account after password confirmation.
  """
  def delete_account(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    password = params["password"] || get_in(params, ["user", "password"])

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required."})

      is_nil(password) or password == "" ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Password is required to delete account."})

      not User.valid_password?(user, password) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Incorrect password."})

      true ->
        case Repo.delete(user) do
          {:ok, _deleted_user} ->
            conn
            |> put_status(:ok)
            |> json(%{message: "Account permanently deleted."})

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete account.", errors: errors})
        end
    end
  end

  def edit(conn, _params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    render(conn, :edit, user: user)
  end

  # 1. UPDATE EMAIL (Legacy HTML / Form route)
  def update(conn, %{"action" => "update_email", "user" => user_params}) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

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

  # 2. UPDATE PASSWORD (Legacy HTML / Form route)
  def update(conn, %{"action" => "update_password", "user" => user_params}) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    case Accounts.update_user_password(user, user_params) do
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

      {:ok, {:error, %Ecto.Changeset{} = changeset}} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})

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

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  # 3. CONFIRM EMAIL CHANGE
  @spec confirm_email(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def confirm_email(conn, %{"token" => token}) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    case Accounts.update_user_email(user, token) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Email changed successfully.",
          data: %{
            user: %{id: updated_user.id, email: updated_user.email}
          }
        })

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Email change link is invalid or it has expired."})
    end
  end

  @doc """
  POST /api/v1/settings/preferences
  PUT /api/v1/settings/preferences
  Updates user settings (such as visual theme) and locale in the database.
  """
  def update_preferences(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required."})

      true ->
        theme = params["theme"]
        locale = params["locale"] || params["language"]

        current_settings = user.settings || %{}
        updated_settings = if theme, do: Map.put(current_settings, "theme", theme), else: current_settings

        changes = %{settings: updated_settings}
        changes = if locale, do: Map.put(changes, :locale, locale), else: changes

        changeset =
          user
          |> Ecto.Changeset.cast(changes, [:settings, :locale])

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Preferences updated successfully.",
              data: %{
                user: %{
                  id: updated_user.id,
                  locale: updated_user.locale,
                  settings: updated_user.settings,
                  theme: get_in(updated_user.settings || %{}, ["theme"])
                }
              }
            })

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update preferences.", errors: errors})
        end
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:user]

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end

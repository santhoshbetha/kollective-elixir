defmodule KollectiveWeb.Admin.CryptoBackupController do
  use KollectiveWeb, :controller
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Chats.Participant

  @doc """
  POST /api/v1/auth/backup_key
  Saves the locally encrypted browser-key backup payload string securely to PostgreSQL [1.4].
  """
  def store_backup(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    backup_params = Map.get(params, "backup", params)

    case User.backup_changeset(user, backup_params) |> Repo.update() do
      {:ok, updated_user} ->
        if public_key = backup_params["public_key"] do
          from(p in Participant, where: p.user_id == ^updated_user.id)
          |> Repo.update_all(set: [public_key: public_key])
        end

        json(conn, %{
          status: "success",
          message: "Zero-Knowledge identity backup archived securely."
        })

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to parse backup schemas fields parameters."})
    end
  end

  @doc """
  GET /api/v1/auth/recover_key
  Pulls down the locked ciphertext block configuration so a new device can decrypt it locally [1.4].
  """
  def fetch_backup(conn, _params) do
    case conn.assigns[:current_user] || conn.assigns[:user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized", data: %{has_key: false, has_backup: false}})

      user ->
        user = Repo.get(User, user.id) || user

        if user.encrypted_private_key_backup && user.backup_salt do
          json(conn, %{
            data: %{
              encrypted_private_key_backup: user.encrypted_private_key_backup,
              backup_salt: user.backup_salt,
              public_key: user.public_key,
              has_key: true,
              has_backup: true
            }
          })
        else
          json(conn, %{
            data: %{
              encrypted_private_key_backup: nil,
              backup_salt: nil,
              public_key: user.public_key,
              has_key: false,
              has_backup: false
            }
          })
        end
    end
  end
end


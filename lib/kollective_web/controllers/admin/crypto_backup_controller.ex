defmodule KollectiveWeb.Admin.CryptoBackupController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Accounts.User

  @doc """
  POST /api/v1/auth/backup_key
  Saves the locally encrypted browser-key backup payload string securely to PostgreSQL [1.4].
  """
  def store_backup(conn, params) do
    user = conn.assigns[:current_user] || conn.assigns[:user]
    backup_params = Map.get(params, "backup", params)

    case User.backup_changeset(user, backup_params) |> Repo.update() do
      {:ok, _updated_user} ->
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
    user = conn.assigns[:current_user] || conn.assigns[:user]
    user = (user && Repo.get(User, user.id)) || user

    if user.encrypted_private_key_backup && user.backup_salt do
      json(conn, %{
        data: %{
          encrypted_private_key_backup: user.encrypted_private_key_backup,
          backup_salt: user.backup_salt
        }
      })
    else
      conn
      |> put_status(:not_found)
      |> json(%{
        error: "No secure encrypted identity backups registered for this account handle."
      })
    end
  end
end

defmodule Kollective.Repo.Migrations.AddEncryptedBackupToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Stores the base64 encrypted private key string chunk safely [1.4]
      add(:encrypted_private_key_backup, :text, null: true)
      # Stores the random salt used during PBKDF2 generation on the client browser
      add(:backup_salt, :string, null: true)
    end
  end
end

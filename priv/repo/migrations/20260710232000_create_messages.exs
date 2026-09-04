defmodule Kollective.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :encrypted_content, :binary
      add :sender_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :file_url, :string
      add :encrypted_file_key, :binary
      add :file_iv, :binary
      add :file_name, :string

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:sender_id])
  end
end

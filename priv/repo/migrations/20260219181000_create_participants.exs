# You need a composite index on [:user_id, :conversation_id] to make fetching a user's list of active chats extremely fast.
defmodule Kollective.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:conversation_participants) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :last_read_at, :utc_datetime
      # Store the RSA/Curve25519 Public Key
      add :public_key, :text

      timestamps()
    end

    create_if_not_exists unique_index(:conversation_participants, [:user_id, :conversation_id])
    create_if_not_exists index(:conversation_participants, [:conversation_id])
  end
end

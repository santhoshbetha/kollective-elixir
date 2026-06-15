#You need a composite index on [:user_id, :conversation_id] to make fetching a user's list of active chats extremely fast.
defmodule Kollective.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:conversation_participants) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime
      add :public_key, :text # Store the RSA/Curve25519 Public Key

      timestamps()
    end

    create unique_index(:conversation_participants, [:user_id, :conversation_id])
    create index(:conversation_participants, [:conversation_id])
  end
end

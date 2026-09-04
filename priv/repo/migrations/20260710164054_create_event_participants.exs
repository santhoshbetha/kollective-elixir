defmodule Kollective.Repo.Migrations.CreateEventParticipants do
  use Ecto.Migration

  def change do
    create table(:event_participants, primary_key: false) do
      # Enforces unified Ecto.ULID binary format globally
      add :id, :binary_id, primary_key: true

      # ─── CORE RELATIONSHIPS ───
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # ─── STATE FIELDS ───
      add :status, :string, default: "going", null: false

      timestamps()
    end

    # ⚡ CRITICAL CONSTRAINT: Enforces a compound unique index
    # This prevents the same user from registering multiple RSVPs for a single event node
    create unique_index(:event_participants, [:event_id, :user_id])

    # Performance Index: Optimizes fetching all events joined by a specific user profile
    create index(:event_participants, [:user_id])
  end
end

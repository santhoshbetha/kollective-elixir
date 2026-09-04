defmodule Kollective.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      # Enforces system-wide ULID sortable binary keys universally
      add :id, :binary_id, primary_key: true

      # ─── CORE ATTRIBUTES ───
      add :type, :string, null: false
      add :read, :boolean, default: false, null: false
      # Ecto.Enum stores cleanly as string
      add :urgency, :string, default: "medium", null: false
      # Native PostgreSQL JSONB block maps to :map
      add :metadata, :map, default: "{}", null: false

      # ─── RELATIONAL OWNERSHIP ───
      # The recipient who views the notification block
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # The actor who triggered the notification pipeline
      add :actor_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # ─── OPTIONAL EXPLICIT LINKS ───
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all)
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all)

      # ─── POLYMORPHIC LINK TARGETS ───
      add :target_id, :binary_id
      add :target_type, :string

      timestamps()
    end

    # ─── OPTIMIZED PERFORMANCE INDICES ───

    # 1. Faster activity feed lookups sorted chronologically
    create index(:notifications, [:user_id, :inserted_at])

    # 2. Speeds up fast grouping lookups to collapse consecutive repetitive metrics
    create index(:notifications, [:user_id, :target_id, :type])

    # 3. High-efficiency partial index for instantaneous unread notification badges
    create index(:notifications, [:user_id],
             where: "read = false",
             name: :notifications_unread_count_index
           )
  end
end

defmodule Kollective.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :string, null: false
      add :metadata, :map, default: "{}", null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :organization_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(updated_at: false)
    end

    # 🚀 HIGH-PERFORMANCE PRODUCTION INDEXES:
    # Speeds up private organization dashboard ledger queries
    create index(:audit_logs, [:organization_id])

    # Speeds up chronological global root admin ledger queries where organization_id is nil
    create index(:audit_logs, [:inserted_at, :id])

    create index(:audit_logs, [:actor_id])
  end
end

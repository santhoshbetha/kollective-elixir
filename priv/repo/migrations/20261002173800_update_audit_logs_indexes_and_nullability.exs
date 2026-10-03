defmodule Kollective.Repo.Migrations.UpdateAuditLogsIndexesAndNullability do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      modify :organization_id, :binary_id, null: true
    end

    drop_if_exists index(:audit_logs, [:organization_id, :inserted_at])
    create_if_not_exists index(:audit_logs, [:organization_id])
    create_if_not_exists index(:audit_logs, [:inserted_at, :id])
  end
end

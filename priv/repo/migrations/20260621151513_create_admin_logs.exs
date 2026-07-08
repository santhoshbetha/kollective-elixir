defmodule Kollective.Repo.Migrations.CreateAdminLogs do
  use Ecto.Migration

  def change do
    create table(:admin_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :target_id, :binary_id
      add :target_type, :string, default: "Event"
      # High-performance JSONB storage blocks
      add :metadata, :jsonb, default: "{}", null: false

      # Maps index tracking back to your admin profiles
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps()
    end

    # Composite indexing layout to support real-time Admin Panel Audit Feed scans instantly
    create index(:admin_logs, [:user_id, :inserted_at])
    create index(:admin_logs, [:action, :inserted_at])
  end
end

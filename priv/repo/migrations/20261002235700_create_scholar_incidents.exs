defmodule Kollective.Repo.Migrations.CreateScholarIncidents do
  use Ecto.Migration

  def change do
    create table(:scholar_incidents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, default: "pending", null: false
      add :flag_type, :string
      add :description, :text
      add :target_username, :string
      add :orcid_id, :string
      add :historical_count, :integer, default: 0
      add :scraped_count, :integer, default: 0
      add :last_sync_at, :utc_datetime

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)
      add :resolved_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:scholar_incidents, [:status])
    create index(:scholar_incidents, [:user_id])
  end
end

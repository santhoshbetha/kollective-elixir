# priv/repo/migrations/XXXXXXXXXXXXXX_create_abuse_reports.exs
defmodule Kollective.Repo.Migrations.CreateAbuseReports do
  use Ecto.Migration

  def change do
    create table(:abuse_reports) do
      add :comment, :text, null: false
      # "open" | "resolved"
      add :status, :string, null: false, default: "open"
      # "candidate" | "post" | "comment"
      add :target_type, :string, null: false
      add :target_id, :integer, null: false
      add :reporter_id, :binary_id, null: false
      add :assigned_moderator_id, :binary_id, null: true

      timestamps()
    end

    create index(:abuse_reports, [:status])
  end
end

defmodule Kollective.Repo.Migrations.CreateApplicationJuries do
  use Ecto.Migration

  def change do
    create table(:red_badge_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :evidence_text, :text, null: false
      add :evidence_media_urls, {:array, :string}, default: []
      add :status, :string, default: "voting", null: false
      add :target_badge_type, :string, default: "ProfessionalTeal", null: false
      add :applicant_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:red_badge_applications, [:applicant_id])
    create index(:red_badge_applications, [:status])

    create table(:application_juries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vote, :string, default: "unvoted", null: false
      add :voted_at, :naive_datetime

      add :application_id,
          references(:red_badge_applications, type: :binary_id, on_delete: :delete_all),
          null: false

      add :juror_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:application_juries, [:application_id, :juror_id],
             name: :application_juries_application_id_juror_id_index
           )
  end
end

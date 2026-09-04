# priv/repo/migrations/20260722183200_create_candidacy_applications_ledger.exs
defmodule Kollective.Repo.Migrations.CreateCandidacyApplicationsLedger do
  use Ecto.Migration

  def change do
    # Track the active validation applications filed by citizens
    create table(:candidacy_applications) do
      # "pending_vouches" | "under_jury_review" | "approved" | "rejected"
      add :status, :string, null: false, default: "pending_vouches"
      add :declared_profession, :string, null: false
      add :linkedin_url, :string, null: true
      add :employment_proof_url, :string, null: false
      add :vouches_count, :integer, null: false, default: 0

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:candidacy_applications, [:user_id], where: "status != 'rejected'")

    # Join table to track who vouched for who, ensuring one account cannot vouch multiple times
    create table(:candidacy_vouches, primary_key: false) do
      add :application_id, references(:candidacy_applications, on_delete: :delete_all),
        null: false

      add :vouching_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create unique_index(:candidacy_vouches, [:application_id, :vouching_user_id])
  end
end

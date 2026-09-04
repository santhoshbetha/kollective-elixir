defmodule Kollective.Repo.Migrations.CreatePollsArchitecture do
  use Ecto.Migration

  def change do
    # ─── 1. BASE POLLS TABLE ───
    create table(:polls, primary_key: false) do
      # Enforces system-wide ULID sortable binary keys universally
      add :id, :binary_id, primary_key: true

      add :multiple, :boolean, default: false, null: false
      add :non_anonymous, :boolean, default: false, null: false
      add :votes_count, :integer, default: 0, null: false
      add :expired, :boolean, default: false, null: false
      add :expires_at, :utc_datetime, null: false

      # Parent Relationship linking directly back to its Post node context
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:polls, [:post_id])
    create index(:polls, [:expired, :expires_at])

    # ─── 2. POLL OPTIONS TABLE ───
    create table(:poll_options, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ⚡ FIXED: Updated from :text to :title to match your exact PollOption schema field name
      add :title, :string, null: false

      add :votes_count, :integer, default: 0, null: false

      # Relational link tying choices to their respective poll node container
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:poll_options, [:poll_id])

    # ─── 3. POLL VOTES TABLE ───
    create table(:poll_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false

      add :option_id, references(:poll_options, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    # ⚡ UNIQUE COMPOSITE KEY CONSTRAINT (Single or Multiple Choice tracking support option)
    # Named explicitly to match your changeset unique_constraint name parameter target rule
    create unique_index(:poll_votes, [:user_id, :poll_id],
             name: :poll_votes_user_id_poll_id_index
           )

    create index(:poll_votes, [:option_id])
  end
end

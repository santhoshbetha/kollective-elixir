# priv/repo/migrations/20260715170500_add_deadlines_and_local_offices.exs
defmodule Kollective.Repo.Migrations.AddDeadlinesAndLocalOffices do
  use Ecto.Migration

  def change do
    # ⏱️ Create a potential table for crowdsourced election lifecycle information
    create table(:election_deadlines) do
      # e.g., "congress", "state_senate", "state_rep", "municipal", "county"
      add :office_level, :string, null: false
      # e.g., "TX-10", "city_id_or_name"
      add :district_code, :string, null: false
      # e.g., "City Council District B", "County Commissioner"
      add :sub_local_name, :string, null: true
      add :election_date, :date, null: false
      add :application_deadline, :date, null: false
      # e.g., "TX", "CA" (For student boundary isolation)
      add :state, :string, null: false
      add :logged_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps()
    end

    create unique_index(:election_deadlines, [:office_level, :district_code, :sub_local_name])

    # 🗳️ Potential update candidate video schema parameter limits to allow local offices
    alter table(:candidate_videos) do
      # Potentially binds local office strings directly to pitches
      add :sub_local_name, :string, null: true
    end
  end
end

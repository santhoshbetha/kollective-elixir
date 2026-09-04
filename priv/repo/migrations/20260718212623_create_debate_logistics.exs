# priv/repo/migrations/XXXXXXXXXXXXXX_create_debate_logistics.exs
defmodule Kollective.Repo.Migrations.CreateDebateLogistics do
  use Ecto.Migration

  def change do
    # A. Primary Debate Event Cards Table
    create table(:debate_events) do
      add :title, :string, null: false
      add :date_time, :utc_datetime, null: false
      add :venue_address, :string, null: false
      # "congress", "state_senate", "state_rep"
      add :office_level, :string, null: false
      # e.g., "TX-10", "SD-24"
      add :district_code, :string, null: false
      # Live stream pointer link
      add :broadcast_node_url, :string, null: true

      timestamps()
    end

    create index(:debate_events, [:office_level, :district_code])

    # B. Connected Operational Shifts Array Table (Has-Many Relation)
    create table(:debate_shifts) do
      # e.g., "AV Stream Technician"
      add :role_name, :string, null: false
      add :max_volunteers, :integer, null: false, default: 2
      add :debate_event_id, references(:debate_events, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:debate_shifts, [:debate_event_id])

    # C. Many-To-Many Join Table: Binds volunteers safely to claimed slots
    create table(:debate_shifts_volunteers, primary_key: false) do
      add :debate_shift_id, references(:debate_shifts, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:debate_shifts_volunteers, [:debate_shift_id, :user_id])
  end
end

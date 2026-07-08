defmodule Kollective.Repo.Migrations.AddMissingUserColumns do
  use Ecto.Migration

  def up do
    alter table(:users) do
      # Identity
      add :username, :string
      add :display_name, :string
      add :alias_name, :string
      add :first_name, :string
      add :last_name, :string

      # Location
      add :location, :string
      add :state, :string
      add :city_id, :string
      add :city_name, :string
      add :precinct, :string

      # Political Districts (FK to political_districts table which uses integer PK)
      add :district_l1_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      add :district_l2_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      add :district_l3_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      # Candidate profile
      add :professional_credentials, :string
      add :candidate_role, :string
      add :verification_id, :string
      add :verified_title, :string
      add :official_website, :string

      # Activity timestamps
      add :last_active_at, :utc_datetime
      add :last_digest_emailed_at, :naive_datetime
      add :last_post_at, :naive_datetime
      add :last_read_at, :utc_datetime
      add :last_seen_at, :utc_datetime

      # Suspension
      add :suspended_at, :utc_datetime
      add :suspension_reason, :string

      # Age / DOB
      add :age, :integer
      add :birth_year, :integer

      # Chat
      add :accepts_chat_messages, :boolean

      # Embedded notification settings (stored as jsonb)
      add :notification_settings, :map
    end

    create_if_not_exists unique_index(:users, [:username])
  end

  def down do
    drop_if_exists unique_index(:users, [:username])

    alter table(:users) do
      remove :username
      remove :display_name
      remove :alias_name
      remove :first_name
      remove :last_name
      remove :location
      remove :state
      remove :city_id
      remove :city_name
      remove :precinct
      remove :district_l1_id
      remove :district_l2_id
      remove :district_l3_id
      remove :professional_credentials
      remove :candidate_role
      remove :verification_id
      remove :verified_title
      remove :official_website
      remove :last_active_at
      remove :last_digest_emailed_at
      remove :last_post_at
      remove :last_read_at
      remove :last_seen_at
      remove :suspended_at
      remove :suspension_reason
      remove :age
      remove :birth_year
      remove :accepts_chat_messages
      remove :notification_settings
    end
  end
end

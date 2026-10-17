defmodule Kollective.Repo.Migrations.CreateModerationAppeals do
  use Ecto.Migration

  def change do
    create table(:moderation_appeals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :incident_id, :binary_id, null: false
      add :user_id, :binary_id, null: false
      add :reason, :text, null: false
      # "pending" | "approved" | "rejected"
      add :status, :string, default: "pending"
      add :country_code, :string, null: false
      add :origin_node_atom, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:moderation_appeals, [:status, :country_code])
  end
end

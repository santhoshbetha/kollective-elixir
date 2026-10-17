defmodule Kollective.Repo.Migrations.CreateSovereignOperators do
  use Ecto.Migration

  def change do
    create table(:sovereign_operators, primary_key: false) do
      # Username serves as the unique text primary key across nodes
      add :username, :string, primary_key: true
      # "moderator" | "admin"
      add :role, :string, null: false
      add :granted_by, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sovereign_operators, [:username])
  end
end

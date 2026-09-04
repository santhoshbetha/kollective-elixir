defmodule Kollective.Repo.Migrations.AddCivicDeadlinesAndMunicipalRoles do
  use Ecto.Migration

  def change do
    create index(:election_deadlines, [:state])
  end
end

defmodule Kollective.Repo.Migrations.AddRepresentativeNameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :representative_name, :string
    end
  end
end

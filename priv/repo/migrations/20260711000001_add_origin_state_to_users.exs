defmodule Kollective.Repo.Migrations.AddOriginStateToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :origin_state, :string
    end
  end
end

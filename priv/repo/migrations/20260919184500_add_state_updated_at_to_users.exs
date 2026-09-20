defmodule Kollective.Repo.Migrations.AddStateUpdatedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :state_updated_at, :utc_datetime
    end
  end
end

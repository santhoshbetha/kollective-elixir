defmodule Kollective.Repo.Migrations.AddVouchFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :account_tier, :integer, default: 0, null: false
      add :metadata, :map, default: "{}", null: false
    end
  end
end

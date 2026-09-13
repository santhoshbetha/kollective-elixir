defmodule Kollective.Repo.Migrations.AddEditCountToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :edit_count, :integer, default: 0, null: false
    end
  end
end

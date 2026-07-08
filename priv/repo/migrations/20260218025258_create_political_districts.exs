defmodule Kollective.Repo.Migrations.CreatePoliticalDistricts do
  use Ecto.Migration

  def change do
    create table(:political_districts) do
      add :name, :string, null: false
      # 1, 2, or 3
      add :level, :integer, null: false
      # e.g., "MLA Constituency"
      add :type_label, :string
      add :state, :string
      # e.g., "US"
      add :country, :string, null: false

      # The self-referencing foreign key for your parent/child self-join
      add :parent_id, references(:political_districts, on_delete: :nilify_all)

      timestamps()
    end

    create index(:political_districts, [:parent_id, :id])
  end
end

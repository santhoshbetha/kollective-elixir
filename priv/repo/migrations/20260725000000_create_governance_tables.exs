defmodule Kollective.Repo.Migrations.CreateGovernanceTables do
  use Ecto.Migration

  def change do
    create table(:political_offices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :country_code, :string, null: false
      add :office_id, :string, null: false
      add :category, :string, null: false
      add :title, :string, null: false
      add :scope, :string, null: false
      add :desc, :text
      add :area_type, :string
      add :term_years, :integer
      add :qualifications, :map, default: "{}"
      add :run_note, :text
      add :state_restriction, :string
      add :district_restriction, :string

      timestamps()
    end

    create unique_index(:political_offices, [
             :country_code,
             :office_id,
             :state_restriction,
             :district_restriction
           ])

    create table(:geo_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :country_code, :string, null: false
      add :level, :integer, null: false
      add :name, :string, null: false
      add :local_type, :string, null: false
      add :area_type, :string
      add :lgd_code, :integer
      add :geom, :geometry
      add :parent_id, references(:geo_nodes, type: :binary_id, on_delete: :nothing)

      timestamps()
    end

    create index(:geo_nodes, [:country_code, :level])
    create index(:geo_nodes, [:parent_id])

    create table(:pincode_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pincode, :string, null: false

      add :geo_node_id, references(:geo_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:pincode_mappings, [:pincode])
  end
end

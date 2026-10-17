defmodule Kollective.Repo.Migrations.AddFieldsToScholarIncidents do
  use Ecto.Migration

  def change do
    alter table(:scholar_incidents) do
      add :country_code, :string
      add :origin_node_atom, :string
      add :leased_by_id, :binary_id
      add :leased_until, :utc_datetime
      add :reporter_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :post_id, references(:posts, on_delete: :nilify_all, type: :binary_id)
    end

    create index(:scholar_incidents, [:status, :country_code])
    create index(:scholar_incidents, [:country_code])
    create index(:scholar_incidents, [:leased_until])
    create index(:scholar_incidents, [:leased_by_id])
    create index(:scholar_incidents, [:reporter_id])
    create index(:scholar_incidents, [:post_id])
  end
end

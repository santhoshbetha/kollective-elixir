defmodule Kollective.Repo.Migrations.AddContactAndLocationToClassifieds do
  use Ecto.Migration

  def change do
    alter table(:classifieds) do
      add :email, :string
      add :phone_number, :string
      add :district_id, references(:political_districts, type: :binary_id, on_delete: :nilify_all)
      add :geom, :geometry
    end

    create index(:classifieds, [:email])
    create index(:classifieds, [:district_id])
    create index(:classifieds, [:geom], using: :gist)
  end
end

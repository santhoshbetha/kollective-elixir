defmodule Kollective.Repo.Migrations.AddOriginCountyToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add_if_not_exists :origin_county, :string
    end

    create_if_not_exists index(:posts, [:origin_county])
  end
end

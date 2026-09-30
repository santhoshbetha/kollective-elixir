defmodule Kollective.Repo.Migrations.AddImageFieldsToBusinesses do
  use Ecto.Migration

  def change do
    alter table(:businesses) do
      add_if_not_exists :profile_image_url, :string
      add_if_not_exists :is_image_processed, :boolean, default: false
    end
  end
end

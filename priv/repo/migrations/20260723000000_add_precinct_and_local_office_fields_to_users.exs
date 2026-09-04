defmodule Kollective.Repo.Migrations.AddPrecinctAndLocalOfficeFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :precinct_number, :string, null: true
      add :town_name, :string, null: true
      add :is_inside_city, :boolean, default: false
      add :applicable_office_ids, {:array, :string}, default: []
    end

    alter table(:candidate_videos) do
      add :status, :string, default: "published"
      add :thumbnail_url, :string, null: true
      add :description, :text, null: true
      add :scope, :string, null: true
      add :target_district, :string, null: true
      add :target_state, :string, null: true
      add :target_country, :string, default: "US"
      add :likes_count, :integer, default: 0
    end
  end
end

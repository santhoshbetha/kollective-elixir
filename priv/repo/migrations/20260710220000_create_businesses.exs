defmodule Kollective.Repo.Migrations.CreateBusinesses do
  use Ecto.Migration

  def change do
    create table(:businesses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false, default: "proposals"
      add :category, :string, null: false, default: "other"
      add :sub_category, :string, null: false, default: "general_other"
      add :address, :string
      add :city, :string
      add :state, :string
      add :zip, :string
      add :country, :string, null: false, default: "US"
      add :email, :string
      add :phone, :string
      add :website, :string
      add :year_established, :integer
      add :number_of_employees, :integer
      add :legal_structure, :string
      add :profile_image_url, :string
      add :district_l1, :string
      add :district_l2, :string
      add :district_l3, :string
      add :city_id, references(:cities, type: :binary_id, on_delete: :nilify_all)
      add :location, :geometry
      add :verification_status, :string, null: false, default: "unverified"
      add :metadata, :map, null: false, default: "{}"
      add :verification_token, :string
      add :verified_at, :utc_datetime
      add :upvotes_count, :integer, null: false, default: 0
      add :comments_count, :integer, null: false, default: 0
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:businesses, [:user_id])
    create index(:businesses, [:city_id])
    create index(:businesses, [:type])
    create index(:businesses, [:verification_status])
    # Geospatial GIST index for location searches
    create index(:businesses, [:location], using: :gist)

    create table(:business_upvotes, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      timestamps()
    end

    create index(:business_upvotes, [:user_id])
    create index(:business_upvotes, [:business_id])

    create table(:business_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :parent_id, references(:business_comments, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:business_comments, [:parent_id])
    create index(:business_comments, [:user_id])
    create index(:business_comments, [:business_id])
  end
end

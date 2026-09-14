defmodule Kollective.Repo.Migrations.CreateClassifieds do
  use Ecto.Migration

  def change do
    create table(:classifieds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :category, :string, null: false
      add :price, :string, null: false
      add :neighborhood, :string, null: false
      add :description, :text, null: false
      add :duration_days, :integer, default: 7, null: false
      add :expires_at, :utc_datetime, null: false
      add :status, :string, default: "active", null: false
      add :location, :string
      add :images, {:array, :string}, default: []
      add :contact_info, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:classifieds, [:category])
    create index(:classifieds, [:neighborhood])
    create index(:classifieds, [:status, :expires_at])
    create index(:classifieds, [:user_id])
  end
end

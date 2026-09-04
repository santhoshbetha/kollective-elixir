defmodule Kollective.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      # ─── PRIMARY KEY ───
      add :id, :binary_id, primary_key: true

      # ─── CORE RELATIONSHIPS ───
      add :post_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      # Fixed to match schema (foreign_key: :created_by)
      add :created_by, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # Organization context linking layout
      add :organization_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :origin_city_id, references(:cities, type: :binary_id, on_delete: :nilify_all)

      # ─── TEXT DETAILS ───
      add :title, :string, null: false
      add :description, :text
      add :category, :string, default: "standard", null: false
      add :participation_format, :string, default: "in_person", null: false
      add :join_mode, :string, default: "free", null: false
      add :event_status, :string, default: "published", null: false
      add :timezone, :string

      # ─── ASSETS ───
      add :banner_url, :string
      add :logo_url, :string
      add :show_banner, :boolean, default: true, null: false

      # ─── TIMING ───
      add :start_time, :utc_datetime
      add :end_time, :utc_datetime

      # ─── COUNTERS ───
      add :participants_count, :integer, default: 0, null: false
      add :participation_request_count, :integer, default: 0, null: false
      add :comments_count, :integer, default: 0, null: false

      # ─── VENUE & ADDRESS DETAILS ───
      add :location_name, :string
      add :location_url, :string
      add :street, :string
      add :postal_code, :string
      add :locality, :string
      add :region, :string
      add :city_name, :string
      add :country, :string

      # ─── GEOSPATIAL & JURISDICTIONS ───
      add :latitude, :float
      add :longitude, :float
      # PostGIS field configuration (assumes PostGIS extension is active)
      add :location, :geometry

      # Ecto.Enum maps to string
      add :target_scope, :string, default: "local", null: false
      add :origin_district_l1, :string
      add :origin_district_l2, :string
      add :origin_district_l3, :string
      add :origin_state, :string
      add :origin_country, :string, default: "US", null: false

      # ─── UNSTRUCTURED PAYLOAD ───
      add :metadata, :map, default: "{}", null: false

      timestamps()
    end

    # ─── PERFORMANCE INDICES ───
    create index(:events, [:created_by])

    # Fast composite query index matching your chronological ULID schema layout
    create index(:events, [:organization_id, :id])
  end
end

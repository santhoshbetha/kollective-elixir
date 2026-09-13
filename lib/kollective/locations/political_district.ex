defmodule Kollective.Locations.PoliticalDistrict do
  use Kollective.Schemas.Schema

  schema "political_districts" do
    field :name, :string
    # 1, 2, or 3, => district_l1, district_l2, or district_l3
    field :level, :integer
    # e.g., "MLA Constituency" or "Congressional District"
    field :type_label, :string
    field :state, :string
    # e.g., "IN" or "US"
    field :country, :string

    field :external_id, :string

    # Native PostGIS geometry field type
    field :geom, Geo.PostGIS.Geometry

    # The "Self-Join"
    belongs_to :parent, Kollective.Locations.PoliticalDistrict

    # The Inverse (Optional): To see all sub-districts
    has_many :sub_districts, Kollective.Locations.PoliticalDistrict, foreign_key: :parent_id

    timestamps()
  end

  def changeset(district, attrs) do
    district
    |> cast(attrs, [:name, :level, :country, :external_id, :state, :geom, :parent_id, :type_label])
    |> validate_required([:name, :level, :country, :external_id, :geom])
  end
end

# create index(:political_districts, [:parent_id, :id])

defmodule Kollective.Governance.GeoNode do
  use Kollective.Schemas.Schema

  schema "geo_nodes" do
    # "US", "IN", "BR"
    field :country_code, :string
    # 1=State, 2=District, 3=Block/City, 4=Panchayat/Ward
    field :level, :integer
    # "Karnataka", "Anantapur", "Amadagur"
    field :name, :string
    # "State", "District", "Gram Panchayat", "ULB"
    field :local_type, :string
    # "urban" | "rural" | nil
    field :area_type, :string, default: nil
    # Unique LGD tracking key code
    field :lgd_code, :integer, default: nil
    # Nullable if relying entirely on LGD text chains
    field :geom, Geo.PostGIS.Geometry, default: nil

    belongs_to :parent, Kollective.Governance.GeoNode, foreign_key: :parent_id
    has_many :children, Kollective.Governance.GeoNode, foreign_key: :parent_id

    timestamps()
  end

  def changeset(geo_node, attrs) do
    geo_node
    |> cast(attrs, [
      :country_code,
      :level,
      :name,
      :local_type,
      :area_type,
      :lgd_code,
      :parent_id,
      :geom
    ])
    |> validate_required([:country_code, :level, :name, :local_type])
    |> validate_inclusion(:area_type, ["urban", "rural", nil])
  end
end

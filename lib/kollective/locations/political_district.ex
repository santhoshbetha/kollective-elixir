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

    # The "Self-Join"
    belongs_to :parent, Kollective.Locations.PoliticalDistrict

    # The Inverse (Optional): To see all sub-districts
    has_many :sub_districts, Kollective.Locations.PoliticalDistrict, foreign_key: :parent_id

    timestamps()
  end
end

# create index(:political_districts, [:parent_id, :id])

defmodule Kollective.Locations.PoliticalDistrict do
  use Ecto.Schema

  schema "political_districts" do
    field :name, :string
    field :level, :integer         # 1, 2, or 3, => district_l1, district_l2, or district_l3
    field :type_label, :string     # e.g., "MLA Constituency" or "Congressional District"
    field :state, :string
    field :country, :string        # e.g., "IN" or "US"

    # The "Self-Join"
    belongs_to :parent, Kollective.Locations.PoliticalDistrict

    # The Inverse (Optional): To see all sub-districts
    has_many :sub_districts, Kollective.Locations.PoliticalDistrict, foreign_key: :parent_id

    timestamps()
  end
end

#create index(:political_districts, [:parent_id, :id])

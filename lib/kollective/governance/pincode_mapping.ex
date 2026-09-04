defmodule Kollective.Governance.PincodeMapping do
  use Kollective.Schemas.Schema

  schema "pincode_mappings" do
    field :pincode, :string
    belongs_to :geo_node, Kollective.Governance.GeoNode

    timestamps()
  end

  def changeset(pincode_mapping, attrs) do
    pincode_mapping
    |> cast(attrs, [:pincode, :geo_node_id])
    |> validate_required([:pincode, :geo_node_id])
    |> validate_length(:pincode, is: 6)
  end
end

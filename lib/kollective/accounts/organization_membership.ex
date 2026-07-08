defmodule Kollective.Accounts.OrganizationMembership do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending

    # Both foreign keys point back to columns in your main users table!
    belongs_to :user, Kollective.Accounts.User, foreign_key: :user_id
    belongs_to :organization, Kollective.Accounts.User, foreign_key: :organization_id

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :organization_id, :role, :status])
    |> validate_required([:user_id, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    # Ensure a user cannot duplicate requests to the same organization
    |> unique_constraint([:user_id, :organization_id], name: :org_memberships_user_org_index)
  end
end

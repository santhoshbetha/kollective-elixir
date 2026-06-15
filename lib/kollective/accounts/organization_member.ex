defmodule Kollective.Accounts.OrganizationMember do
  use Kollective.Schemas.Schema

  schema "organization_members" do
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending

    belongs_to :organization, Kollective.Accounts.Organization
    belongs_to :user, Kollective.Accounts.User

    timestamps()
  end
end

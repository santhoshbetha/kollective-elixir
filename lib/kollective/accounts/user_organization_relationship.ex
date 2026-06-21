#Follow Organization" feature, so users can subscribe to an entire newspaper or group
#and see all their multi-district posts in one unified feed

#1. Since users follow organizations (a different table than users), we create a dedicated join table.
#This keeps the high-traffic user_relationships table lean.

defmodule Kollective.Accounts.UserOrganizationRelationship do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_organization_relationships" do
    belongs_to :user, Kollective.Accounts.User
    belongs_to :organization, Kollective.Accounts.Organization

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:user_id, :organization_id])
    |> validate_required([:user_id, :organization_id])
    |> unique_constraint([:user_id, :organization_id])
  end
end

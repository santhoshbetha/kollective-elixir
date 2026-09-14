defmodule Kollective.Accounts.OrganizationMembership do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "organization_memberships" do
    field :role, Ecto.Enum, values: [:admin, :contributor, :owner], default: :contributor

    field :status, Ecto.Enum,
      values: [:pending, :approved, :active, :rejected, :removed],
      default: :pending

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
    |> validate_account_types()
  end

  defp validate_account_types(changeset) do
    user_id = get_field(changeset, :user_id)
    org_id = get_field(changeset, :organization_id)

    if user_id && org_id do
      user = Kollective.Repo.get(Kollective.Accounts.User, user_id)
      org = Kollective.Repo.get(Kollective.Accounts.User, org_id)

      cond do
        user && user.type == :organization ->
          add_error(changeset, :user_id, "an organization cannot be a member")

        org && org.type != :organization ->
          add_error(changeset, :organization_id, "must be an organization")

        true ->
          changeset
      end
    else
      changeset
    end
  end
end

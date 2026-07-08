defmodule Kollective.Civic.Vouch do
  use Kollective.Schemas.Schema # Injects chronological ULIDs and UTC timestamps [INDEX]

  schema "user_vouches" do
    belongs_to :voucher, Kollective.Accounts.User, foreign_key: :voucher_id
    belongs_to :vouchee, Kollective.Accounts.User, foreign_key: :vouchee_id

    field :origin_state, :string

    # Records exactly which level matched: "l1" (Federal), "l2" (Senate), "l3" (Assembly)
    field :matched_tier, :string
    field :district_value, :string

    timestamps()
  end

  def changeset(vouch, attrs) do
    vouch
    |> cast(attrs, [:voucher_id, :vouchee_id, :origin_state, :matched_tier, :district_value])
    |> validate_required([:voucher_id, :vouchee_id, :origin_state, :matched_tier, :district_value])
    |> validate_inclusion(:matched_tier, ~w(l1 l2 l3))
    |> validate_identity_separation()
    # A voucher can only vouch for a vouchee once per specific state tier
    |> unique_constraint([:voucher_id, :vouchee_id, :origin_state, :matched_tier],
      name: :vouches_voucher_vouchee_tier_unique_index,
      message: "You have already verified this neighbor for this political tier."
    )
  end

  defp validate_identity_separation(changeset) do
    v1 = get_field(changeset, :voucher_id)
    v2 = get_field(changeset, :vouchee_id)

    if v1 && v1 == v2 do
      add_error(changeset, :vouchee_id, "Self-verification signatures are structurally impossible.")
    else
      changeset
    end
  end
end

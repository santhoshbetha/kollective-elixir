defmodule Kollective.Civic.Vouch do
  # Injects chronological ULIDs and UTC timestamps
  use Kollective.Schemas.Schema

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
    |> validate_required([
      :voucher_id,
      :vouchee_id,
      :origin_state,
      :matched_tier,
      :district_value
    ])
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
      add_error(
        changeset,
        :vouchee_id,
        "Self-verification signatures are structurally impossible."
      )
    else
      changeset
    end
  end

  @doc """
  Calculates the total count of valid peer vouches received by a given user from the user_vouches table.
  """
  def count_for_user(nil), do: 0
  def count_for_user(%{id: id}), do: count_for_user(id)

  def count_for_user(user_id) when is_binary(user_id) or is_integer(user_id) do
    import Ecto.Query

    Kollective.Repo.one(
      from v in __MODULE__,
        where: v.vouchee_id == ^user_id,
        select: count(v.id)
    ) || 0
  end

  def count_for_user(_), do: 0

  @doc """
  Calculates a map of %{user_id => vouch_count} for a list of user_ids from the user_vouches table.
  """
  def batch_count_for_users(user_ids) when is_list(user_ids) do
    import Ecto.Query

    valid_ids =
      user_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    if valid_ids == [] do
      %{}
    else
      from(v in __MODULE__,
        where: field(v, :vouchee_id) in ^valid_ids,
        group_by: v.vouchee_id,
        select: {v.vouchee_id, count(v.id)}
      )
      |> Kollective.Repo.all()
      |> Map.new(fn {id, cnt} -> {to_string(id), cnt} end)
    end
  end

  def batch_count_for_users(_), do: %{}
end

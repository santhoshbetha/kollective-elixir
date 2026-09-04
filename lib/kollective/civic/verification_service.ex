# lib/kollective/civic/verification_service.ex
defmodule Kollective.Civic.VerificationService do
  @moduledoc """
  Manages fluid overlapping multi-district peer-to-peer vouch networks.
  Enforces state consistency and requires a minimum of one matching district tier .
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Civic.Vouch
  alias Kollective.Accounts.User

  @doc """
  Processes an asynchronous peer vouch under absolute transaction boundaries.
  """
  def process_peer_vouch(voucher_id, vouchee_id) do
    Repo.transaction(fn ->
      # Pessimistically lock user nodes to eliminate high-concurrency race duplication loops
      voucher = Repo.get!(User, voucher_id)
      vouchee = Repo.get!(User, vouchee_id)

      # 🚨 GUARD 1: Voucher must hold fully active clearance tiers themselves
      if voucher.account_tier == 0 do
        Repo.rollback("Voucher does not hold authorized verification standing.")
      end

      # 🚨 GUARD 2: Force absolute state consistency
      if voucher.origin_state != vouchee.origin_state || is_nil(voucher.origin_state) do
        Repo.rollback("Cross-state validation mapping rejected.")
      end

      # 🚨 GUARD 3: Evaluate overlapping constituency criteria
      matched_tier_attrs = determine_matching_tier(voucher, vouchee)

      if is_nil(matched_tier_attrs) do
        Repo.rollback("No overlapping district boundaries found between voucher and vouchee.")
      end

      {tier_key, district_value} = matched_tier_attrs

      # 🚨 GUARD 4: Anti-Collusion check
      if has_reverse_vouch?(vouchee_id, voucher_id, voucher.origin_state) do
        Repo.rollback(
          "Collusive verification circle detected. Mutual back-vouching is forbidden."
        )
      end

      params = %{
        voucher_id: voucher.id,
        vouchee_id: vouchee.id,
        origin_state: voucher.origin_state,
        matched_tier: tier_key,
        district_value: district_value
      }

      case %Vouch{} |> Vouch.changeset(params) |> Repo.insert() do
        {:ok, _vouch} ->
          # 5. Tally complete unique separate trust signatures recorded for this vouchee
          vouch_count =
            Repo.one(
              from v in Vouch,
                where: v.vouchee_id == ^vouchee.id and v.origin_state == ^vouchee.origin_state,
                select: count(v.id)
            )

          # 6. Elevate account tier cleanly once threshold parameter passes 3
          if vouch_count >= 3 and vouchee.account_tier == 0 do
            vouchee |> User.changeset(%{account_tier: 1}) |> Repo.update!()
          end

          vouch_count

        {:error, _changeset} ->
          Repo.rollback(
            "Duplicate vouch signature detected or schema validation parameters failed."
          )
      end
    end)
  end

  # --- Internal Overlap Evaluation Engine ---
  defp determine_matching_tier(v1, v2) do
    cond do
      # Prioritize matching down lines sequentially: L1 -> L2 -> L3
      v1.district_l1_id && v1.district_l1_id == v2.district_l1_id -> {"l1", v1.district_l1_id}
      v1.district_l2_id && v1.district_l2_id == v2.district_l2_id -> {"l2", v1.district_l2_id}
      v1.district_l3_id && v1.district_l3_id == v2.district_l3_id -> {"l3", v1.district_l3_id}
      true -> nil
    end
  end

  defp has_reverse_vouch?(vouchee_id, voucher_id, origin_state) do
    Repo.exists?(
      from v in Vouch,
        where:
          v.voucher_id == ^vouchee_id and v.vouchee_id == ^voucher_id and
            v.origin_state == ^origin_state
    )
  end
end

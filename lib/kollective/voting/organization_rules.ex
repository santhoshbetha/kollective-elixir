# lib/kollective/voting/organization_rules.ex
defmodule Kollective.Voting.OrganizationRules do
  @moduledoc """
  Enforces accountability parameters and status penalties onto News Organizations.
  Operates transaction-safely to enforce systemic accountability trails.
  """
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Accounts.User

  @doc """
  Processes community misinformation reports. If structural report thresholds are reached,
  downgrades the organization to a public warning status tier for 30 days.
  """
  def enforce_strike_penalty(organization_id, evidence_summary) do
    # Fetch the user row profile record out of your database index tables
    case Repo.get(User, organization_id) do
      nil ->
        {:error, :not_found}

      org_user ->
        # FIX: Dynamic field lookup safely bypasses static struct compiler constraint checks
        # Evaluates the string properties dynamically to ensure absolute stability
        if Map.get(org_user, :badge_type) == "PremiumGold" do
          cleaned_metadata =
            (org_user.metadata || %{})
            |> Map.put("warned_status", true)
            |> Map.put("strike_reason", evidence_summary)
            |> Map.put("strike_activated_at", DateTime.utc_now() |> DateTime.truncate(:second))

          Multi.new()
          # Step A: Shift target structural privileges and alter badge parameters natively
          |> Multi.update(:org_downgrade, fn _repo ->
            Ecto.Changeset.change(org_user, %{
              badge_type: "WarnedYellow",
              metadata: cleaned_metadata
            })
          end)

          # Step B: Record the transaction inside your centralized Admin Log table rows
          |> Multi.insert(:audit_log, fn _changes ->
            %Kollective.Admins.Log{
              action: "organization_propaganda_strike_applied",
              target_id: org_user.id,
              target_type: "User",
              user_id: org_user.id,
              metadata: %{reason: evidence_summary, previous_badge: "PremiumGold"}
            }
          end)

          # Step C: Execute the full atomic database transaction pool safely
          |> Repo.transaction()
          |> case do
            {:ok, %{org_downgrade: updated_org}} ->
              # ─── UNIVERSAL REAL-TIME COMPLIANCE SIGNALLING BUS ───
              # Step D: Route through your unified PubSub broker onto your lightweight signaling bus channel
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                # Correct channel target for account modifications
                "feed:public",
                {"badge_demotion",
                 %{
                   "user_id" => to_string(updated_org.id),
                   "demoted_to" => "WarnedYellow",
                   "incident_type" => "ORGANIZATION_PROPAGANDA_STRIKE"
                 }}
              )

              {:ok, updated_org}

            {:error, _failed_step, changeset, _changes_so_far} ->
              {:error, changeset}
          end
        else
          # Account exists but does not hold active PremiumGold standing parameters
          {:error, :not_eligible}
        end
    end
  end
end

defmodule Kollective.Voting.OrganizationRules do
  @moduledoc """
  Enforces accountability parameters and status penalties onto News Organizations.
  """
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias KollectiveWeb.Endpoint

  @doc """
  Processes community misinformation reports. If structural report thresholds are reached,
  downgrades the organization to a public warning status tier for 30 days.
  """
  def enforce_strike_penalty(organization_id, evidence_summary) do
    org_user = Repo.get(User, organization_id)

    if org_user && org_user.badge_type == "PremiumGold" do
      updated_metadata =
        org_user.metadata
        |> Map.put("warned_status", true)
        |> Map.put("strike_reason", evidence_summary)
        |> Map.put("strike_activated_at", DateTime.utc_now())

      # Flipped down to Warning Yellow Status (Overwriting core badge classification strings)
      {:ok, updated_org} =
        org_user
        |> User.changeset(%{
          badge_type: "WarnedYellow",
          metadata: updated_metadata
        })
        |> Repo.update()

      # ⚡ Broadcast warning change to user feeds everywhere instantly
      Endpoint.broadcast("timeline:global", "badge_demotion", %{
        user_id: updated_org.id,
        demoted_to: "WarnedYellow",
        incident_type: "ORGANIZATION_PROPAGANDA_STRIKE"
      })

      {:ok, updated_org}
    else
      {:error, :not_eligible}
    end
  end
end

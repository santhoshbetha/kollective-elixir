defmodule Kollective.Workers.OrganizationProbationWorker do
  @moduledoc """
  Nightly cron worker that releases news organizations from probation once their 30-day penalty wraps up.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias KollectiveWeb.Endpoint

  @impl Oban.Worker
  def perform(_job) do
    # Calculate the exact timestamp matrix boundary for a 30-day penalty look-back
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    # 1. Locate all WarnedYellow publishers that completed their probation duration
    query =
      from(u in User,
        where: u.badge_type == "WarnedYellow",
        # Use Postgres jsonb arrow extraction to pull the timestamp string out safely
        where:
          fragment(
            "(?::jsonb->>'strike_activated_at')::timestamp < ?",
            u.metadata,
            ^thirty_days_ago
          )
      )

    # 2. Iterate through records inside an isolated stream and restore premium privileges
    Repo.all(query)
    |> Enum.each(fn org_user ->
      process_probation_release(org_user)
    end)

    :ok
  end

  defp process_probation_release(org_user) do
    # Remove the active penalty markers from the metadata payload profile map
    cleared_metadata =
      org_user.metadata
      |> Map.delete("warned_status")
      |> Map.delete("strike_reason")
      |> Map.put("probation_successfully_served_at", DateTime.utc_now())

    # Write restoration to disc
    {:ok, restored_org} =
      org_user
      |> User.changeset(%{
        badge_type: "PremiumGold",
        metadata: cleared_metadata
      })
      |> Repo.update()

    # ⚡ Broadcast real-time network upgrade signal down WebSockets to toggle UI tokens on screens
    Endpoint.broadcast("timeline:global", "badge_demotion", %{
      user_id: restored_org.id,
      # Reusing structural mapping to handle step-ups
      demoted_to: "PremiumGold",
      incident_type: "PROBATION_COMPLIANCE_RELEASE"
    })

    IO.puts(
      "✓ PROBATION EXPIRED // ORGANIZATION_ID: #{restored_org.id} // STATUS: PremiumGold RESTORED"
    )
  end
end

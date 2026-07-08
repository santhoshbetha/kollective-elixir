defmodule Kollective.Voting.ScholarIntegrity do
  @moduledoc """
  Audits scholar metric deltas during background updates and reports system compliance failures.
  """
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias KollectiveWeb.Endpoint

  @doc """
  Evaluates old metadata values against newly scraped records to spot red flags.
  """
  def evaluate_sync_metrics(user, old_metadata, new_publication_count) do
    old_count = Map.get(old_metadata, "publication_count", 0)

    cond do
      # 🚨 CASE 1: Drastic decrease in publications (indicates records wiped or hidden)
      old_count > 0 and new_publication_count < old_count * 0.5 ->
        flag_account(
          user,
          :drastic_work_reduction,
          "Publication registry dropped sharply from #{old_count} to #{new_publication_count}."
        )

      # 🚨 CASE 2: Total registry wipeout
      new_publication_count == 0 ->
        flag_account(user, :zero_records, "ORCID record contains zero public research assets.")

      true ->
        {:ok, :compliant}
    end
  end

  defp flag_account(user, violation_type, details_text) do
    # 1. Update account metadata to lock badge visibility
    updated_metadata =
      user.metadata
      |> Map.put("under_investigation", true)
      |> Map.put("flag_reason", details_text)

    # Freeze badge to prevent misinformation propagation across your social app
    {:ok, _user} =
      user
      |> User.changeset(%{badge_type: "ClassicBlue", metadata: updated_metadata})
      |> Repo.insert_or_update()

    # ⚡ BROADCAST INSTANT TEARDOWN SYSTEM SIGNAL OVER CHANNELS
    Endpoint.broadcast("timeline:global", "badge_demotion", %{
      user_id: user.id,
      demoted_to: "ClassicBlue",
      incident_type: to_string(violation_type)
    })

    # 2. Fire telemetry/incident log to your app's moderation team
    dispatch_moderation_ticket(user.id, violation_type, details_text)

    {:error, :flagged_for_investigation}
  end

  defp dispatch_moderation_ticket(user_id, violation_type, details_text) do
    # Connect this block to your app's internal security center/moderator dashboard
    IO.puts(
      "⚠️ SECURITY MODERATION ALERT // USER_ID: #{user_id} // VIOLATION: #{violation_type} // DETAILS: #{details_text}"
    )
  end
end

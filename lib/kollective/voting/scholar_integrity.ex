# lib/kollective/voting/scholar_integrity.ex
defmodule Kollective.Voting.ScholarIntegrity do
  @moduledoc """
  Audits scholar metric deltas during background updates and reports system compliance failures.
  Operates transaction-safely to enforce systemic accountability trails.
  """
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Accounts.User
  require Logger

  @doc """
  Evaluates old metadata values against newly scraped records to spot red flags.
  """
  def evaluate_sync_metrics(%User{} = user, old_metadata, new_publication_count) do
    # Gracefully match atom or string key variants natively from metadata JSONB maps
    old_metadata_map = old_metadata || %{}

    old_count =
      Map.get(old_metadata_map, "publication_count") ||
        Map.get(old_metadata_map, :publication_count) || 0

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
    # 1. Clean and modify the user's nested metadata jsonb map safely in memory
    current_metadata = user.metadata || %{}

    updated_metadata =
      current_metadata
      |> Map.put("under_investigation", true)
      |> Map.put("flag_reason", details_text)
      |> Map.put("flagged_at", DateTime.utc_now() |> DateTime.truncate(:second))

    Multi.new()
    # Step A: Shift target structural privileges and alter badge parameters natively
    |> Multi.update(:user_downgrade, fn _repo ->
      Ecto.Changeset.change(user, %{
        # Downgrade account permissions to stop scholar target overrides
        type: :citizen,
        badge_type: "ClassicBlue",
        metadata: updated_metadata
      })
    end)

    # Step B: Record the transaction inside your centralized compliance incidents table
    |> Multi.insert(:compliance_incident, fn _changes ->
      %Kollective.Admins.Log{
        action: "scholar_integrity_auto_quarantine",
        target_id: user.id,
        target_type: "User",
        # Automated system rule self-trigger marker
        user_id: user.id,
        metadata: %{violation: to_string(violation_type), details: details_text}
      }
    end)

    # Step C: Execute the full atomic database transaction pool safely
    |> Repo.transaction()
    |> case do
      {:ok, %{user_downgrade: updated_user}} ->
        # ─── UNIVERSAL REAL-TIME COMPLIANCE SIGNALLING BUS ───
        # Step D: Route through your unified PubSub broker onto your lightweight signaling bus channel
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          # 🟢 Correct channel target for account modifications
          "feed:public",
          {"badge_demotion",
           %{
             "user_id" => to_string(updated_user.id),
             "demoted_to" => "ClassicBlue",
             "incident_type" => to_string(violation_type)
           }}
        )

        # Trigger asynchronous notifications alert to your app's moderator dashboard desk
        dispatch_moderation_ticket(updated_user.id, violation_type, details_text)

        {:error, :flagged_for_investigation}

      {:error, _failed_step, changeset, _changes_so_far} ->
        {:error, changeset}
    end
  end

  defp dispatch_moderation_ticket(user_id, violation_type, details_text) do
    Logger.warning(
      "🛡️ COMPLIANCE DESK RUNTIME WARNING // USER_ID: #{user_id} // VIOLATION: #{violation_type} // DETAILS: #{details_text}"
    )
  end
end

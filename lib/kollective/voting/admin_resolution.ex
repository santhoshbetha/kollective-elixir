defmodule Kollective.Voting.AdminResolution do
  @moduledoc """
  Processes administrative multi-stage overrides to settle compliance tickets and restore user access.
  Operates transaction-safely to enforce systemic accountability trails.
  """
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Accounts.User

  @doc """
  Executes an atomic transaction block to restore a scholar's frozen status,
  marks the open internal compliance ticket as resolved, and logs the action .
  """
  def process_scholar_reinstatement(user_id, admin_user_id) do
    # FIXED: Check if the user exists first to prevent a runtime nil crash!
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      # Using a plain variable here is fine, but the metadata line below is what fixes the warning!
      user ->
        # FIX: Clean the map directly since Ecto guarantees metadata is never nil
        cleaned_metadata =
          user.metadata
          |> Map.delete("under_investigation")
          |> Map.delete("flag_reason")
          |> Map.put("approved_by_admin_id", to_string(admin_user_id))
          |> Map.put("reinstated_at", DateTime.utc_now())

        Multi.new()
        # Step A: Re-promote user privileges back to premium Scholar standing natively
        |> Multi.update(:user_restore, fn _repo ->
          user
          |> Ecto.Changeset.change(%{
            # FIXED: Crucial privilege promotion to bypass citizen targeting bounds
            type: :scholar,
            badge_type: "verified_scholar",
            metadata: cleaned_metadata
          })
        end)

        # Step B: Mark the internal platform compliance logging ticket as resolved
        |> Multi.update_all(
          :ticket_close,
          from(i in "compliance_incidents", where: i.user_id == ^user.id and i.status == "open"),
          set: [
            status: "resolved",
            resolved_by: to_string(admin_user_id),
            updated_at: DateTime.utc_now()
          ]
        )

        # Step C: Write the unalterable transaction into your central Admin Log table
        |> Multi.insert(:audit_log, fn _changes ->
          %Kollective.Admins.Log{
            action: "admin_scholar_reinstatement",
            target_id: user.id,
            target_type: "User",
            user_id: admin_user_id,
            metadata: %{username: user.username}
          }
        end)

        # Step D: Execute the full atomic database transaction pool
        |> Repo.transaction()
        |> case do
          {:ok, %{user_restore: restored_user}} ->
            # Step E: FIXED - Live broadcast across standard pubsub to change UI frames instantly
            Phoenix.PubSub.broadcast(
              Kollective.PubSub,
              "feed:public",
              {:badge_demotion,
               %{
                 user_id: restored_user.id,
                 demoted_to: "Scholar",
                 incident_type: "ADMIN_REINSTATEMENT"
               }}
            )

            {:ok, restored_user}

          {:error, _failed_step, changeset, _changes_so_far} ->
            {:error, changeset}
        end
    end
  end
end

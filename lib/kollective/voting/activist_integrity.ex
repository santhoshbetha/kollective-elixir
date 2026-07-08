defmodule Kollective.Voting.ActivistIntegrity do
  @moduledoc """
  Handles community recall mechanisms to protect the network against co-opted activist badges.
  """
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias KollectiveWeb.Endpoint

  @doc """
  Instantly revokes a Signal Red badge if a community recall petition meets verification thresholds,
  broadcasting the demotion real-time to active user browser windows.
  """
  def execute_community_recall(target_user_id, audit_reason_text) do
    user = Repo.get!(User, target_user_id)

    if user.badge_type == "SignalRed" do
      updated_metadata =
        (user.metadata || %{})
        |> Map.put("recalled_at", DateTime.utc_now())
        |> Map.put("recall_justification", audit_reason_text)

      # 1. Demote to Classic Blue standing inside an isolated atomic database write
      {:ok, demoted_user} =
        user
        |> User.changeset(%{badge_type: "ClassicBlue", metadata: updated_metadata})
        |> Repo.update()

      # 2. ⚡ REUSED DEMOTION BROADCAST PIPELINE
      # Blasts the teardown payload down the WebSocket to drop the red shield icon instantly from feeds
      Endpoint.broadcast("timeline:global", "badge_demotion", %{
        user_id: demoted_user.id,
        demoted_to: "ClassicBlue",
        incident_type: "ACTIVIST_COMMUNITY_RECALL"
      })

      {:ok, demoted_user}
    else
      {:error, :not_eligible}
    end
  end
end

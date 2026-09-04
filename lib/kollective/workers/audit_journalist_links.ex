defmodule Kollective.Workers.AuditJournalistLinks do
  @moduledoc """
  Nightly background worker tracking the structural integrity of journalist portfolio URLs.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  alias Kollective.Repo
  alias Kollective.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Repo.get(User, user_id)

    # Proceed strictly if they are an active journalist with a portfolio tracking URL
    if user && user.badge_type == "ProfessionalTeal" &&
         Map.has_key?(user.metadata, "portfolio_url") do
      portfolio_url = user.metadata["portfolio_url"]

      case check_url_status(portfolio_url) do
        :active ->
          # Timestamp the verification check log inside JSONB metadata fields
          updated_metadata = Map.put(user.metadata, "link_last_checked_at", DateTime.utc_now())
          user |> User.changeset(%{metadata: updated_metadata}) |> Repo.update()
          :ok

        :dead ->
          # 🚨 COMPLIANCE CORRECTION ACTION HOOK
          # Automatically strip the badge and convert account back to standard ClassicBlue
          flag_corrupted_journalist(
            user,
            "Portfolio URL returned a dead endpoint link error (404 / connection failure)."
          )

          :ok
      end
    else
      :ok
    end
  end

  defp check_url_status(url) do
    # In live environments, execute a lightweight, fast HTTP HEAD request to preserve resources:
    # case Req.head(url) do
    #   {:ok, %{status: 200}} -> :active
    #   _ -> :dead
    # end

    # Mocking check for internal scripting example rules
    if String.contains?(url, "dead-link") || String.contains?(url, "404") do
      :dead
    else
      :active
    end
  end

  defp flag_corrupted_journalist(user, structural_reason) do
    # FIX: Clean the map safely since Ecto guarantees metadata is never nil
    updated_metadata =
      user.metadata
      |> Map.put("under_investigation", true)
      |> Map.put("flag_reason", structural_reason)
      |> Map.put("penalized_at", DateTime.utc_now())

    # Atomic downgrade write action block
    {:ok, updated_user} =
      user
      |> User.changeset(%{
        # Strips corporate privileges atomically to secure district targeting bounds
        type: :citizen,
        badge_type: "ClassicBlue",
        metadata: updated_metadata
      })
      |> Repo.update()

    # ─── UNIVERSAL REAL-TIME COMPLIANCE SIGNALLING BUS ───
    # FIX: Route through your unified PubSub broker onto your lightweight signaling bus channel
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      # 🟢 Correct channel target for account modifications
      "feed:public",
      {"badge_demotion",
       %{
         "user_id" => to_string(updated_user.id),
         "demoted_to" => "ClassicBlue",
         "incident_type" => "JOURNALIST_LINK_BROKEN"
       }}
    )

    # Trigger administrative log tracking entry
    %Kollective.Admins.Log{
      action: "journalist_quarantine_auto_flag",
      target_id: updated_user.id,
      target_type: "User",
      # Automated system rule self-trigger marker
      user_id: updated_user.id,
      metadata: %{reason: structural_reason, timestamp: DateTime.utc_now()}
    }
    |> Kollective.Repo.insert!()

    {:ok, updated_user}
  end
end

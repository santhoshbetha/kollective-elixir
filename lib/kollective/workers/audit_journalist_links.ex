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
    updated_metadata =
      user.metadata
      |> Map.put("under_investigation", true)
      |> Map.put("flag_reason", structural_reason)

    # Atomic downgrade write action block
    {:ok, _user} =
      user
      |> User.changeset(%{badge_type: "ClassicBlue", metadata: updated_metadata})
      |> Repo.update()

    # ⚡ Real-time web alert broadcast block to pull the teal badge from active client browser views instantly
    KollectiveWeb.Endpoint.broadcast("timeline:global", "badge_demotion", %{
      user_id: user.id,
      demoted_to: "ClassicBlue",
      incident_type: "JOURNALIST_LINK_BROKEN"
    })

    # Trigger admin ticket tracking dispatch
    IO.puts(
      "⚠️ SECURITY MODERATION ALERT // JOURNALIST_ID: #{user.id} // REASON: #{structural_reason}"
    )
  end
end

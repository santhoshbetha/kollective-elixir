defmodule Kollective.Voting.TimeupResolution do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Voting.{RedBadgeApplication, ApplicationJury}
  alias Kollective.Accounts.User

  @doc """
  Runs at the 48-hour mark to count votes and automatically activate or reject the badge.
  """
  def resolve_application(application_id) do
    app = Repo.get(RedBadgeApplication, application_id)

    # Only process if the application hasn't already been modified/closed early
    if app && app.status == "voting" do
      votes =
        Repo.all(
          from aj in ApplicationJury, where: aj.application_id == ^application_id, select: aj.vote
        )

      total_votes = length(votes)
      approve_count = Enum.count(votes, &(&1 == "approve"))

      # Check if 75% approval milestone was achieved
      if total_votes > 0 and approve_count / total_votes >= 0.75 do
        activate_red_badge(app)
      else
        reject_application(app)
      end
    end
  end

  defp activate_red_badge(app) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:application, RedBadgeApplication.changeset(app, %{status: "approved"}))
    |> Ecto.Multi.update(
      :user,
      User.changeset(Repo.get(User, app.applicant_id), %{badge_type: "SignalRed"})
    )
    |> Repo.transaction()
  end

  defp reject_application(app) do
    app
    |> RedBadgeApplication.changeset(%{status: "rejected"})
    |> Repo.update()
  end
end

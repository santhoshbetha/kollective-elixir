defmodule Kollective.Voting.ActivistVetting do
  @moduledoc """
  Adapts the core jury routing logic to vet Frontline Activists, Union Leaders, and Whistleblowers.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Voting.{RedBadgeApplication, ApplicationJury}
  alias Kollective.Accounts.User

  @doc """
  Deploys an activist verification application to a randomized, blind jury of 12 active Red-Badge peers.
  """
  def submit_activist_application(applicant_id, evidence_text, media_urls) do
    Ecto.Multi.new()
    # 1. Insert the core application entry matching our early JSON contract schema
    |> Ecto.Multi.insert(
      :application,
      RedBadgeApplication.changeset(%RedBadgeApplication{}, %{
        applicant_id: applicant_id,
        evidence_text: evidence_text,
        evidence_media_urls: media_urls,
        status: "voting"
      })
    )
    # 2. Select 12 randomized Red-Badge holders with zero social graph overlaps
    |> Ecto.Multi.run(:jurors, fn _repo, _changes ->
      fetch_isolated_activist_jurors(applicant_id)
    end)
    # 3. Batch insert the 12 blind juror ballot slots into the database
    |> Ecto.Multi.run(:juries, fn _repo, %{application: app, jurors: jurors} ->
      insert_jury_slots(app.id, jurors)
    end)
    # 4. Enqueue the Oban background worker we built earlier to process the 48-hour timeup resolution
    |> Oban.insert(:oban_job, fn %{application: app} ->
      Kollective.Workers.ResolveVotingTimeup.new(%{application_id: app.id},
        schedule_in: {48, :hours}
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: app, jurors: juror_ids}} ->
        # 5. Broadcast real-time "JURY_DUTY_ASSIGNED" alerts over Phoenix Channels to the selected 12
        Kollective.Voting.Notifier.send_jury_invitations(app.id, juror_ids)
        {:ok, app}

      {:error, _failed_step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp fetch_isolated_activist_jurors(applicant_id) do
    following_ids =
      from(f in "follows", where: f.follower_id == ^applicant_id, select: f.following_id)

    follower_ids =
      from(f in "follows", where: f.following_id == ^applicant_id, select: f.follower_id)

    query =
      from(u in User,
        where: u.badge_type == "SignalRed" and u.id != ^applicant_id,
        where: u.id not in subquery(following_ids),
        where: u.id not in subquery(follower_ids),
        order_by: fragment("RANDOM()"),
        limit: 12,
        select: u.id
      )

    case Repo.all(query) do
      jurors when length(jurors) == 12 ->
        {:ok, jurors}

      _ ->
        {:error,
         "Insufficient independent active Red-Badge holders to initialize an automated jury."}
    end
  end

  defp insert_jury_slots(application_id, juror_ids) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(juror_ids, fn juror_id ->
        %{
          application_id: application_id,
          juror_id: juror_id,
          vote: "unvoted",
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    {count, nil} = Repo.insert_all(ApplicationJury, entries)
    {:ok, count}
  end
end

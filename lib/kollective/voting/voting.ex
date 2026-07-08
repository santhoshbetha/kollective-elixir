defmodule Kollective.Voting.Voting do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Voting.{RedBadgeApplication, ApplicationJury}
  alias Kollective.Accounts.User
  alias Kollective.Voting.ApplicationJury

  @doc """
  Initializes a red badge application and routes it to 12 randomized, non-biased jurors.
  """
  def submit_red_badge_application(applicant_id, evidence_text, media_urls) do
    Ecto.Multi.new()
    # 1. Insert the application entry
    |> Ecto.Multi.insert(
      :application,
      RedBadgeApplication.changeset(%RedBadgeApplication{}, %{
        applicant_id: applicant_id,
        evidence_text: evidence_text,
        evidence_media_urls: media_urls,
        status: "voting"
      })
    )

    # 2. Fetch 12 randomized peer jurors using subqueries to prevent social graph bias
    |> Ecto.Multi.run(:jurors, fn _repo, _changes ->
      fetch_eligible_jurors(applicant_id)
    end)

    # 3. Batch insert the 12 blind juror slots into the database
    |> Ecto.Multi.run(:juries, fn _repo, %{application: app, jurors: jurors} ->
      insert_jury_pool(app.id, jurors)
    end)

    # Schedule Oban within the Multi transaction block so it rolls back if DB write fails
    |> Oban.insert(:oban_job, fn %{application: app} ->
      Kollective.Workers.ResolveVotingTimeup.new(%{application_id: app.id},
        schedule_in: {48, :hours}
      )
    end)

    # 4. Commit everything together safely
    |> Repo.transaction()
    |> case do
      {:ok, %{application: app, jurors: jurors}} ->
        # Asynchronously blast out channel push notifications to the 12 picked devices
        Kollective.Voting.Notifier.send_jury_invitations(app.id, jurors)
        {:ok, app}

      {:error, _failed_step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp fetch_eligible_jurors(applicant_id) do
    # Subquery: Who does the applicant follow?
    following_ids =
      from(f in "follows", where: f.follower_id == ^applicant_id, select: f.following_id)

    # Subquery: Who follows the applicant?
    follower_ids =
      from(f in "follows", where: f.following_id == ^applicant_id, select: f.follower_id)

    # Core Query: Get 12 random Red Badge holders with zero overlapping social ties
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
      jurors when length(jurors) == 12 -> {:ok, jurors}
      _ -> {:error, "Insufficient community peers to form an automated decentralized jury pool."}
    end
  end

  defp insert_jury_pool(application_id, juror_ids) do
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

  @doc """
  Safely updates a juror's record if they are assigned to the application and haven't voted yet.
  """
  def record_jury_vote(application_id, juror_id, vote_value) do
    # Find the specific slot assigned to this juror
    query =
      from aj in ApplicationJury,
        where: aj.application_id == ^application_id and aj.juror_id == ^juror_id

    case Repo.one(query) do
      nil ->
        # The user was never selected for this randomized 12-person jury
        {:error, :not_authorized}

      %ApplicationJury{vote: old_vote} when old_vote != "unvoted" ->
        # The user has already submitted a ballot for this case
        {:error, :already_voted}

      %ApplicationJury{} = jury_record ->
        # Update the entry with a timestamped ballot
        jury_record
        |> ApplicationJury.changeset(%{
          vote: vote_value,
          voted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end
end

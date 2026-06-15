defmodule Kollective.Polls.Polls  do
  import Ecto.Query
  alias Kollective.Repo

  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Polls.{Poll, PollOption, PollVote}


  def get_poll_results(poll_id, user_id \\ nil) do
    Poll

    |> where([p], p.id == ^poll_id)
    |> preload([:options])
    |> Repo.one()

    |> case do
      nil -> nil
      poll ->
        poll
        |> populate_user_vote_data(user_id)
    end
  end

  defp populate_user_vote_data(poll, nil), do: poll
  defp populate_user_vote_data(poll, user_id) do
    # Check if this specific user has voted on this poll
    own_votes =
      from(v in PollVote,
        where: v.poll_id == ^poll.id and v.user_id == ^user_id,
        select: v.option_id)

      |> Repo.all()

    %{poll |
      voted: not Enum.empty?(own_votes),
      own_votes: own_votes
    }
  end

  # Real-Time Push logic to update these percentages in React as soon as a new vote is cast?
  # Update your cast_vote function (or wherever you handle the successful Repo.transaction)
  # to push the updated results.
  defp broadcast_poll_update(poll_id) do
    # Fetch fresh results (without a specific user_id so it's a generic update)
    poll = get_poll_results(poll_id)

    # Broadcast to the specific topic for this poll
    KollectiveWeb.Endpoint.broadcast("poll:#{poll_id}", "results_updated", %{
      votes_count: poll.votes_count,
      options: Enum.map(poll.options, fn o ->
        %{id: o.id, votes_count: o.votes_count}
      end)
    })
  end


  def cast_votes(user_id, poll_id, option_ids) when is_list(option_ids) do
    poll = Repo.get!(Poll, poll_id)

    cond do
      # 1. Check Expiry
      DateTime.compare(DateTime.utc_now(), poll.expires_at) == :gt ->
        {:error, :poll_expired}

      # 2. Check if already voted
      Repo.exists?(from v in PollVote, where: v.poll_id == ^poll_id and v.user_id == ^user_id) ->
        {:error, :already_voted}

      # 3. If not 'multiple', ensure only one option is sent
      !poll.multiple and length(option_ids) > 1 ->
        {:error, :too_many_options}

      true ->
        execute_voting_transaction(user_id, poll_id, option_ids)
    end
  end

  defp execute_voting_transaction(user_id, poll_id, option_ids) do
    Multi.new()
    # 1. Insert vote records for all selected options

    |> Multi.insert_all(:insert_votes, PollVote,
        Enum.map(option_ids, fn id ->
          %{user_id: user_id, poll_id: poll_id, option_id: id, inserted_at: DateTime.utc_now()}
        end))

    # 2. Increment the 'votes_count' for each specific option
    |> Multi.update_all(:inc_options,
        from(o in PollOption, where: o.id in ^option_ids),
        inc: [votes_count: 1])

    # 3. Increment the total 'votes_count' for the poll
    # Note: Mastodon usually increments this per-option, not per-user

    |> Multi.update_all(:inc_poll,
        from(p in Poll, where: p.id == ^poll_id),
        inc: [votes_count: length(option_ids)])

    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        # Trigger the real-time broadcast we built earlier
        broadcast_poll_update(poll_id)
        {:ok, :voted}
      {:error, _name, value, _changes} -> {:error, value}
    end
  end

end

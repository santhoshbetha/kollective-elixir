defmodule Kollective.Polls.Polls do
  import Ecto.Query
  alias Kollective.Repo

  alias Ecto.Multi
  alias Kollective.Polls.{Poll, PollOption, PollVote}

  # NEW: Fetch a single poll and attach user-specific "I voted" data
  # GET "/polls/:id" uses this
  def get_poll_results(poll_id, user_id \\ nil) do
    Poll
    |> where([p], p.id == ^poll_id or p.post_id == ^poll_id)
    |> preload([:options])
    |> Repo.one()
    |> case do
      nil ->
        nil

      poll ->
        poll
        |> populate_user_vote_data(user_id)
    end
  end

  # NEW: Helper to attach "Has the current user voted on this?"
  # Used by the API and Socket
  defp populate_user_vote_data(poll, nil), do: poll

  defp populate_user_vote_data(poll, user_id) do
    # Check if this specific user has voted on this poll
    own_votes =
      from(v in PollVote,
        where: v.poll_id == ^poll.id and v.user_id == ^user_id,
        select: v.option_id
      )
      |> Repo.all()

    %{poll | voted: not Enum.empty?(own_votes), own_votes: own_votes}
  end

  # NEW: Send updates to Phoenix Channels so the UI updates instantly
  # Place this at the bottom of lib/kollective/polls/polls.ex
  defp broadcast_poll_update(poll_id) do
    # Fetch fresh results (without a specific user_id so it's a generic update)
    poll = get_poll_results(poll_id)

    if poll do
      # Broadcast to the specific topic for this poll
      KollectiveWeb.Endpoint.broadcast("poll:#{poll_id}", "results_updated", %{
        votes_count: poll.votes_count,
        options:
          Enum.map(poll.options, fn o ->
            %{id: o.id, votes_count: o.votes_count}
          end)
      })
    end
  end

  # POST /polls/:poll_id/votes uses this
  def cast_votes(user_id, poll_id, option_ids) when is_list(option_ids) do
    poll =
      Poll
      |> where([p], p.id == ^poll_id or p.post_id == ^poll_id)
      |> preload([:options])
      |> Repo.one()

    cond do
      is_nil(poll) ->
        {:error, :not_found}

      # 1. Check Expiry
      # 🟢 FIXED: Zone-safe timestamp comparison pattern
      DateTime.diff(DateTime.utc_now(), poll.expires_at) > 0 ->
        {:error, :poll_expired}

      # 2. Check if already voted
      Repo.exists?(from v in PollVote, where: v.poll_id == ^poll.id and v.user_id == ^user_id) ->
        {:error, :already_voted}

      # 3. If not 'multiple', ensure only one option is sent
      !poll.multiple and length(option_ids) > 1 ->
        {:error, :too_many_options}

      true ->
        # Resolve choice indices to actual option IDs if necessary
        sorted_options = Enum.sort_by(poll.options, & {&1.inserted_at, &1.id})

        resolved_option_ids =
          Enum.map(option_ids, fn
            idx when is_integer(idx) ->
              case Enum.at(sorted_options, idx) do
                nil -> nil
                opt -> opt.id
              end

            id when is_binary(id) ->
              case Integer.parse(id) do
                {num, ""} when num >= 0 and num < length(sorted_options) ->
                  case Enum.at(sorted_options, num) do
                    nil -> nil
                    opt -> opt.id
                  end

                _ ->
                  case Enum.find(sorted_options, &(&1.id == id)) do
                    nil -> id
                    opt -> opt.id
                  end
              end

            other ->
              other
          end)
          |> Enum.reject(&is_nil/1)

        if resolved_option_ids == [] do
          {:error, :invalid_option}
        else
          execute_voting_transaction(user_id, poll.id, resolved_option_ids)
        end
    end
  end

  defp execute_voting_transaction(user_id, poll_id, option_ids) do
    # 🟢 FIXED: Truncate to second for structural database accuracy
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    # 1. Insert vote records for all selected options
    |> Multi.insert_all(
      :insert_votes,
      PollVote,
      Enum.map(option_ids, fn id ->
        %{
          id: Ecto.ULID.generate(),
          user_id: user_id,
          poll_id: poll_id,
          option_id: id,
          inserted_at: now,
          # 🟢 FIXED: Pad missing timestamp row element to prevent DB constraint crashes
          updated_at: now
        }
      end)
    )

    # 2. Increment the 'votes_count' for each specific option
    |> Multi.update_all(
      :inc_options,
      from(o in PollOption, where: o.id in ^option_ids),
      inc: [votes_count: 1]
    )

    # 3. Increment the total 'votes_count' for the poll
    # Note: Mastodon usually increments this per-option, not per-user

    |> Multi.update_all(
      :inc_poll,
      from(p in Poll, where: p.id == ^poll_id),
      inc: [votes_count: length(option_ids)]
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        # Trigger the real-time broadcast we built earlier
        broadcast_poll_update(poll_id)
        {:ok, :voted}

      {:error, _name, value, _changes} ->
        {:error, value}
    end
  end
end

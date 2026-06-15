defmodule KollectiveWeb.PollJSON do
  def data(poll) do
    %{
      id: poll.id,
      expires_at: poll.expires_at,
      expired: DateTime.compare(DateTime.utc_now(), poll.expires_at) == :gt,
      multiple: poll.multiple,
      votes_count: poll.votes_count,
      voted: poll.voted,
      own_votes: poll.own_votes,
      options: Enum.map(poll.options, fn option ->
        %{
          id: option.id,
          title: option.title,
          votes_count: option.votes_count,
          # Calculate percentage: (option_votes / total_votes) * 100
          percent: calculate_percent(option.votes_count, poll.votes_count)
        }
      end)
    }
  end

  defp calculate_percent(_opt_votes, 0), do: 0
  defp calculate_percent(opt_votes, total_votes) do
    (opt_votes / total_votes * 100) |> Float.round(1)
  end


  def show(%{poll: poll}) do
    %{data: data(poll)}
  end

  def data2(poll) do
    %{
      id: poll.id,
      expires_at: poll.expires_at,
      expired: DateTime.compare(DateTime.utc_now(), poll.expires_at) == :gt,
      multiple: poll.multiple,
      votes_count: poll.votes_count,
      voted: poll.voted, # Virtual field
      own_votes: poll.own_votes, # Array of option IDs user picked
      options: Enum.map(poll.options, &option_data/1)
    }
  end

  defp option_data(option) do
    %{
      id: option.id,
      title: option.title,
      votes_count: option.votes_count
    }
  end


end

# lib/kollective_web/controllers/posts/poll_json.ex
defmodule KollectiveWeb.PollJSON do
  @moduledoc """
  Unified JSON serializer for interactive Polls and vote tallies.
  """

  @doc """
  Serializes a single poll entity.
  """
  def show(%{poll: poll}), do: show(poll)

  def show(poll) do
    %{data: data(poll)}
  end

  @doc """
  Serializes a list of polls.
  """
  def index(%{polls: polls}), do: index(polls)

  def index(polls) when is_list(polls) do
    Enum.map(polls, &data/1)
  end

  @doc """
  Serializes the poll data map with vote metrics and options.
  """
  def data(poll) do
    expired =
      if Map.has_key?(poll, :expired) and not is_nil(poll.expired) do
        poll.expired
      else
        DateTime.compare(DateTime.utc_now(), poll.expires_at) == :gt
      end

    options =
      case Map.get(poll, :options) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        opts when is_list(opts) -> opts
      end

    votes_count = Map.get(poll, :votes_count) || 0

    %{
      id: to_string(poll.id),
      expires_at: poll.expires_at,
      expired: expired,
      multiple: Map.get(poll, :multiple, false),
      non_anonymous: Map.get(poll, :non_anonymous, false),
      votes_count: votes_count,
      voted: Map.get(poll, :voted, false),
      own_votes: Map.get(poll, :own_votes, []),
      options:
        Enum.map(options, fn option ->
          opt_votes = Map.get(option, :votes_count, 0) || 0

          %{
            id: to_string(option.id),
            title: option.title,
            votes_count: opt_votes,
            percent: calculate_percent(opt_votes, votes_count)
          }
        end)
    }
  end

  defp calculate_percent(_opt_votes, 0), do: 0.0

  defp calculate_percent(opt_votes, total_votes) do
    (opt_votes / total_votes * 100) |> Float.round(1)
  end
end

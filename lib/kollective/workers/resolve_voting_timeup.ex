defmodule Kollective.Workers.ResolveVotingTimeup do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Kollective.Voting.TimeupResolution

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => application_id}}) do
    # Call the logic engine we wrote previously
    case TimeupResolution.resolve_application(application_id) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
      # Handles cases where the application was already resolved
      nil -> :ok
    end
  end
end

# lib/kollective/workers/meili_sync_worker.ex --- for future Meilisearch integration
defmodule Kollective.Workers.MeiliSyncWorker do
  use Oban.Worker, queue: :media, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "action" => "upsert"}}) do
    user = Kollective.Repo.get!(Kollective.Accounts.User, user_id)

    # Clean document shape payload mapping
    document = %{
      id: to_string(user.id),
      username: user.username,
      display_name: user.display_name,
      bio: user.bio
    }

    # Transmit asynchronously straight to your decoupled Meilisearch node
    case Req.post("http://meilisearch:7700/indexes/users/documents", json: [document], headers: [{"Authorization", "Bearer SECRET_KEY"}]) do
      {:ok, %{status: 202}} -> :ok
      _error_failure -> {:error, :sync_retry_triggered}
    end
  end
end

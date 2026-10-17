defmodule Kollective.Workers.EphemeralChatPurger do
  use Oban.Worker, queue: :default, max_attempts: 3
  import Ecto.Query
  require Logger
  alias Kollective.Repo

  @impl Oban.Worker
  def perform(_job) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    Logger.info("⏳ [EPHEMERAL PURGER]: Checking for expired ephemeral message frames...")

    # Query and hard-delete messages whose expiration deadlines have passed
    # Ensure you add an 'expires_at' integer field column to your messages table migration
    {count, _} =
      from(m in "messages", where: not is_nil(m.expires_at) and m.expires_at <= ^now_unix)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info(
        "🗑️ [EPHEMERAL PURGER]: Flushed #{count} expired self-destruct messages out of persistent blocks."
      )
    end

    :ok
  end
end

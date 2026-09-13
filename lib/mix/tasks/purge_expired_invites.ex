# lib/mix/tasks/purge_expired_invites.ex
defmodule Mix.Tasks.PurgeExpiredInvites do
  use Mix.Task
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.OrganizationMembership

  @shortdoc "Purges pending invitations older than 7 days from the database."

  @impl Mix.Task
  def run(_args) do
    # 1. Start your application dependencies (database pool connection)
    Mix.Task.run("app.start")

    Mix.shell().info("=== Starting Expired Invitation Cleanup Process ===")

    # 2. Establish time boundary (7 days ago)
    cutoff_time = DateTime.utc_now() |> DateTime.add(-7, :day)

    # 3. Formulate structural deletion query
    query =
      from m in OrganizationMembership,
        where: m.status == :pending,
        where: m.inserted_at <= ^cutoff_time

    # 4. Atomically purge entries
    case Repo.delete_all(query) do
      {count, nil} ->
        Mix.shell().info(
          "Success: Purged #{count} expired pending invitations from database rows."
        )

      _ ->
        Mix.shell().error("Error: An issue occurred while sweeping invitation tables.")
    end

    Mix.shell().info("=== Cleanup Process Finished ===")
  end
end

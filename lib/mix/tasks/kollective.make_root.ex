# lib/mix/tasks/kollective.make_root.ex
defmodule Mix.Tasks.Kollective.MakeRoot do
  use Mix.Task

  alias Kollective.Repo
  alias Kollective.Accounts.User
  import Ecto.Query

  @shortdoc "Grants root and administrator privileges to a specific user by email or username"

  @moduledoc """
  This Mix Task allows app owners and server operators to grant full root/admin privileges
  to a target user account directly from the command line interface.

  ## Examples

      $ mix kollective.make_root --email owner@example.com
      $ mix kollective.make_root --username admin
      $ mix kollective.make_root owner@example.com

  """

  @impl Mix.Task
  def run(args) do
    # 1. Start application infrastructure so Repo is loaded
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args, switches: [email: :string, username: :string])

    identifier = opts[:email] || opts[:username] || List.first(positional)

    case identifier do
      nil ->
        Mix.shell().error("""
        [ERROR] Missing required user identifier.

        Usage:
          mix kollective.make_root --email user@example.com
          mix kollective.make_root --username admin_handle
          mix kollective.make_root user@example.com
        """)

      term ->
        grant_root_privileges(term)
    end
  end

  defp grant_root_privileges(term) do
    cleaned_term = String.trim(term) |> String.downcase()

    query =
      from u in User,
        where:
          fragment("LOWER(?)", u.email) == ^cleaned_term or
            fragment("LOWER(?)", u.username) == ^cleaned_term,
        limit: 1

    case Repo.one(query) do
      nil ->
        Mix.shell().error("[ERROR] User matching '#{term}' was not found in the database.")

      %User{} = user ->
        changeset =
          Ecto.Changeset.change(user, %{
            is_admin: true,
            is_moderator: true,
            role: :admin
          })

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            Mix.shell().info("""

            =============================================================
            SUCCESS: ROOT & ADMIN PRIVILEGES GRANTED!
            =============================================================
            ID       : #{updated_user.id}
            Username : @#{updated_user.username}
            Email    : #{updated_user.email}
            Role     : #{updated_user.role} (is_admin: #{updated_user.is_admin})
            =============================================================
            """)

          {:error, changeset} ->
            Mix.shell().error(
              "[ERROR] Failed to update user privileges: #{inspect(changeset.errors)}"
            )
        end
    end
  end
end

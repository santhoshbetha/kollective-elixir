defmodule Mix.Tasks.Kollective.Security.LiftCooldowns do
  use Mix.Task
  require Logger

  @shortdoc "Bulk administrator override to instantly lift all security cooldowns and blacklist blocks"

  @moduledoc """
  This Mix Task allows production administrators to safely flush active network bans,
  strike counters, and flagged keyword constraints directly from the server CLI terminal.

  ## Execution Command
  ```bash
  mix kollective.security.lift_cooldowns
  ```
  """

  @impl Mix.Task
  def run(_args) do
    # 1. ⚡ START THE APPLICATION SUPERVISION TREE:
    # This boots up Kollective.Repo, Oban, and crucially, your :kollective_cache Cachex instances.
    Mix.Task.run("app.start")

    Logger.info("CLI_EXECUTION: Initiating administrative bulk security override pass...")

    # 2. INVOKE THE MEMORY WIPE LAYER:
    # Triggers your optimized underlying :ets.select_delete/2 batch block clear
    case Kollective.Security.Security.lift_all_cooldowns() do
      :ok ->
        Logger.info(
          "SUCCESS: Global network firewall blocks and strike history logs have been successfully flushed from RAM."
        )

      error ->
        Logger.error(
          "FAILURE: Bulk override pass encountered an unhandled error condition: #{inspect(error)}"
        )
    end
  end
end

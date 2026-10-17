defmodule Kollective.Chats.MnesiaHydrator do
  use GenServer
  import Ecto.Query
  require Logger

  alias Kollective.Repo
  alias Kollective.Chats.Conversation

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    # Delay initialization for 3 seconds to let libcluster find peer nodes
    # and give Mnesia time to sync existing tables from other running nodes first.
    Process.send_after(self(), :check_and_hydrate, 3000)
    {:ok, opts}
  end

  @impl true
  def handle_info(:check_and_hydrate, state) do
    case :mnesia.table_info(:distributed_chat_groups, :size) do
      0 ->
        Logger.info(
          "🔄 [MNESIA HYDRATOR]: Table ':distributed_chat_groups' is empty. Recovering state from PostgreSQL..."
        )

        hydrate_from_postgres()

      size ->
        Logger.info(
          "✅ [MNESIA HYDRATOR]: Table already has #{size} active chat rooms. Hydration skipped."
        )
    end

    {:noreply, state}
  end

  defp hydrate_from_postgres do
    # 1. Fetch active conversations from your Postgres DB.
    # Note: If your conversations have an 'archived' or 'status' flag, filter by it here
    # so you only load relevant active rooms into memory, keeping RAM low.
    conversations =
      from(c in Conversation, order_by: [desc: c.inserted_at])
      |> Repo.all()

    # 2. Re-populate the Mnesia Cluster
    Enum.each(conversations, fn conversation ->
      # Recreate the exact tuple structure matching your Controller signature
      inserted_at_iso =
        case conversation.inserted_at do
          %DateTime{} = dt -> DateTime.to_iso8601(dt)
          %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
          nil -> DateTime.utc_now() |> DateTime.to_iso8601()
        end

      description = Map.get(conversation, :description, "") || ""
      title = conversation.title || "Group Chat"

      mnesia_record = {
        :distributed_chat_groups,
        to_string(conversation.id),
        title,
        description,
        "cause",
        inserted_at_iso
      }

      :mnesia.transaction(fn -> :mnesia.write(mnesia_record) end)
    end)

    Logger.info(
      "✨ [MNESIA HYDRATOR]: Successfully populated #{length(conversations)} distributed chat rooms into mesh memory."
    )
  end
end

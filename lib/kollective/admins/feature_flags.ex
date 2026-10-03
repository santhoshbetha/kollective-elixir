defmodule Kollective.Admin.FeatureFlags do
  @moduledoc """
  ⚡ IN-MEMORY ETS FEATURE FLAG MATRIX ENGINE
  Handles high-speed microsecond configuration evaluations with zero database overhead.
  """
  use GenServer
  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Admins.FeatureFlag

  @table_name :kollective_feature_flags_cache

  # ─── PUBLIC CLIENT INTERFACE API ───

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  🚀 MICROSECOND READ: Evaluates if a feature flag is enabled straight from RAM cache.
  Usage: if FeatureFlags.enabled?("registration_open"), do: ...
  """
  def enabled?(key) when is_binary(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, enabled}] -> enabled
      # Default safe-fail if flag isn't registered
      [] -> false
    end
  end

  @doc """
  🔑 CORE MUTATION TRANSACTION: Updates a flag in RAM, commits to DB,
  and broadcasts the state change globally over WebSockets in real time.
  """
  def toggle_flag(key, enabled) when is_binary(key) and is_boolean(enabled) do
    GenServer.call(__MODULE__, {:toggle_flag, key, enabled})
  end

  @doc """
  Lists all active feature flag parameters registered inside the engine.
  """
  def list_flags do
    query = from(f in FeatureFlag, order_by: [asc: f.key])
    Repo.all(query)
  end

  # ─── SERVER LIFECYCLE CALLBACKS ───

  @impl true
  def init(_opts) do
    # 1. Spin up an optimized read-heavy in-memory ETS table partition
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])

    # 2. Synchronize memory state parameters with your persistent database entries
    hydrate_cache_from_db()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:toggle_flag, key, enabled}, _from, state) do
    # 1. Upsert directly to the PostgreSQL database table
    result =
      case Repo.get(FeatureFlag, key) do
        nil -> %FeatureFlag{key: key}
        flag -> flag
      end
      |> FeatureFlag.changeset(%{enabled: enabled})
      |> Repo.insert_or_update()

    case result do
      {:ok, updated_flag} ->
        # 2. Update the in-memory ETS RAM cache instantly
        :ets.insert(@table_name, {key, enabled})

        # 3. 📣 REAL-TIME BROADCAST SYSTEM: Pushes the new state to all connected frontends
        payload = %{key: key, enabled: enabled}

        KollectiveWeb.Endpoint.broadcast(
          "admin_notifications:global",
          "feature_flag_toggled",
          payload
        )

        {:reply, {:ok, updated_flag}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  # --- Private Core Hydrator Helpers ---

  defp hydrate_cache_from_db do
    # Default core flags matrix setup definitions
    default_flags = [
      {"registration_open", true,
       "Controls account sign-up locks across the public registration forms."},
      {"voice_broadcast_active", true,
       "Toggles real-time streaming audio emergency megaphone notifications."},
      {"media_transcoding", true,
       "Manages background compression loops for banner and avatar graphic assets."},
      {"public_feeds_enabled", true,
       "Cyber-attack mitigation switch to completely hide unauthenticated timelines."}
    ]

    Enum.each(default_flags, fn {key, default_state, description} ->
      flag =
        case Repo.get(FeatureFlag, key) do
          nil ->
            %FeatureFlag{key: key}
            |> FeatureFlag.changeset(%{enabled: default_state, description: description})
            |> Repo.insert!()

          existing ->
            existing
        end

      # Populates your shared memory table maps
      :ets.insert(@table_name, {flag.key, flag.enabled})
    end)
  end
end

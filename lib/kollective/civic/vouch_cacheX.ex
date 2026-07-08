defmodule Kollective.Civic.VouchCacheX do
  @moduledoc """
  High-performance in-memory key-value store using Erlang Term Storage (ETS)
  to handle single-use, 60-second rotating validation tokens.
  """
  use GenServer

  @table_name :vouch_secure_tokens
  @ttl_seconds 60

  # --- CLIENT INTERFACE API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Generates a cryptographically secure, single-use token valid for 60 seconds.
  """
  def generate_token(user_id) do
    # Generate an un-guessable, URL-safe random cryptographic token string
    secure_token =
      "vouch_tmp_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    expiration_timestamp = System.os_time(:second) + @ttl_seconds

    # Write directly into the fast parallel reading ETS table row layer
    :ets.insert(@table_name, {secure_token, user_id, expiration_timestamp})
    secure_token
  end

  @doc """
  Validates a token payload string. If valid, consumes it instantly (Single-Use Guard)
  and returns the associated target user ID.
  """
  def consume_token(token) do
    current_time = System.os_time(:second)

    case :ets.lookup(@table_name, token) do
      [{^token, user_id, expires_at}] when current_time <= expires_at ->
        # 🚨 THE REPLAY SHIELD: Burn token immediately from memory on first access check
        :ets.delete(@table_name, token)
        {:ok, user_id}

      [{^token, _user_id, _expires_at}] ->
        :ets.delete(@table_name, token)
        {:error, :token_expired}

      [] ->
        {:error, :token_invalid}
    end
  end

  # --- SERVER HANDSHAKE INITIALIZATION CORE ---

  @impl true
  def init(state) do
    # Create an optimized, thread-safe, concurrent reading Erlang memory table matrix
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Schedule a recurring sweeping routine task process to keep memory cleanly pruned
    schedule_garbage_collection()
    {:ok, state}
  end

  @impl true
  def handle_info(:purge_expired_tokens, state) do
    current_time = System.os_time(:second)

    # Match Specification for {token, user_id, expires_at}
    # Matches elements where expires_at (:$1) < current_time
    ms = [
      {
        # Match Head (3-tuple structure)
        {:_, :_, :"$1"},
        # Guard Condition (expires_at < current_time)
        [{:<, :"$1", current_time}],
        # Result body required by select_delete to trigger removal
        [true]
      }
    ]

    :ets.select_delete(@table_name, ms)

    schedule_garbage_collection()
    {:noreply, state}
  end

  defp schedule_garbage_collection do
    # Run a full internal sweep loop cycle every 30 seconds to drop dead records
    Process.send_after(self(), :purge_expired_tokens, 30_000)
  end
end

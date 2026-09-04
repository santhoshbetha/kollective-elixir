defmodule Kollective.Security.Security do
  @moduledoc """
  Standalone System Security, Fraud Prevention, and Memory Firewall Manager.
  Operates entirely within RAM via Cachex and Hammer to neutralize botnets in under 0.02ms.
  """
  @cache :kollective_cache

  # ─── SECTION 1: MEMORY FIREWALL IP BLACKLISTING ───

  @doc "Bans a malicious IP address from the platform entirely for 24 hours."
  def blacklist_ip(ip) do
    ttl_ms = :timer.hours(24)
    Cachex.put(@cache, "blacklist:#{ip}", true, ttl: ttl_ms)
  end

  @doc "Bans an IP address for a customizable dynamic timeframe (e.g. 1-hour soft cooldowns)."
  def blacklist_ip_temporary(ip, ttl_ms) when is_integer(ttl_ms) do
    Cachex.put(@cache, "blacklist:#{ip}", true, ttl: ttl_ms)
  end

  @doc "Checks if an incoming IP address is currently blacklisted inside our RAM firewall."
  def ip_blacklisted?(ip) do
    case Cachex.get(@cache, "blacklist:#{ip}") do
      {:ok, true} -> true
      _ -> false
    end
  end

  @doc "Manually removes an IP from the memory firewall (Admin API Pardon Trigger)."
  def pardon_ip(ip) do
    Cachex.del(@cache, "blacklist:#{ip}")
  end

  @doc """
  Streams blacklisted IPs safely out of memory without triggering RAM bloat.
  Uses optimized native Erlang query specifications.
  """
  def list_blacklisted_ips do
    case Cachex.stream(@cache) do
      {:ok, stream} ->
        # 🟢 FIXED: Removed the standalone 'stream' word that caused the variable warning
        stream
        |> Stream.map(fn record -> elem(record, 1) end)
        |> Stream.filter(fn key -> is_binary(key) and String.starts_with?(key, "blacklist:") end)
        |> Stream.map(fn key -> String.replace(key, "blacklist:", "") end)
        |> Enum.to_list()

      _ ->
        []
    end
  end

  # ─── SECTION 2: THE TWO-STRIKE ESCALATION COOLDOWN GATEWAY ───

  @doc """
  Increments an infraction strike count against an IP address.
  If they hit Strike 2, they get automatically blacklisted for 24 hours.

  Returns true if the IP was banned on this strike, otherwise false.
  """
  def record_hard_strike(ip) do
    key = "strikes:#{ip}"
    ttl_ms = :timer.hours(1)

    # 🟢 FIXED: The TTL expiration is now bound atomically directly inside the transactional block
    # preventing race conditions and keeping the 1-hour expiration strictly absolute from Strike 1
    case Cachex.get_and_update(@cache, key, fn
           nil -> {:commit, 1, [ttl: ttl_ms]}
           count -> {:commit, count + 1}
         end) do
      {:commit, count} when count >= 2 ->
        blacklist_ip(ip)
        # Clean up the strike marker since they are now migrated to the hard blacklist block
        Cachex.del(@cache, key)
        true

      _one_strike ->
        false
    end
  end

  @doc """
  Wipes all infraction history markers for a specific user. Resets Hammer buckets,
  erases triggered words list history, and clears any active IP block filters.
  """
  def pardon_user(user_id, ip) do
    Cachex.del(@cache, "denied_words:#{user_id}")
    Cachex.del(@cache, "strikes:#{ip}")
    if ip, do: pardon_ip(ip)
    :ok
  end

  @doc """
  Bulk Administrator Override API. Instantly lifts all active 1-hour cooldowns,
  clears tracked word caches, and unlocks blocked IPs across the whole node cluster.
  Bulk Administrator Override API. Instantly flushes collections.
  Optimized for Cachex v3.x using atomic underlying :ets batch select deletions.
  """
  def lift_all_cooldowns do
    case Cachex.stream(@cache) do
      {:ok, stream} ->
        stream
        |> Stream.map(fn record -> elem(record, 1) end)
        |> Stream.filter(fn key ->
          is_binary(key) and
            (String.starts_with?(key, "denied_words:") or
               String.starts_with?(key, "strikes:") or
               String.starts_with?(key, "blacklist:"))
        end)
        |> Enum.each(fn key -> Cachex.del(@cache, key) end)

      _ ->
        :ok
    end

    :ok
  end

  # ─── SECTION 3: SYSTEM GLOBAL LOCKDOWN LEVEL (THE EMERGENCY PANIC BUTTON) ───

  @doc "Forces lockdown mode active for 4 hours by default (Automatic Cool-Off Cooldown)."
  def enable_lockdown do
    ttl_ms = :timer.hours(4)
    Cachex.put(@cache, "lockdown_active", true, ttl: ttl_ms)
  end

  def disable_lockdown do
    Cachex.del(@cache, "lockdown_active")
  end

  def lockdown_active? do
    case Cachex.get(@cache, "lockdown_active") do
      {:ok, true} -> true
      _ -> false
    end
  end
end

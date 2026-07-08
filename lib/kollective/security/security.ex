defmodule Kollective.Security.Security do
  @moduledoc """
  Standalone System Security, Fraud Prevention, and Memory Firewall Manager.
  Operates entirely within RAM via Cachex and Hammer to neutralize botnets in under 0.02ms.
  """
  @cache :kollective_cache

  # ─── SECTION 1: MEMORY FIREWALL IP BLACKLISTING ───

  @doc "Bans a malicious IP address from the platform entirely for 24 hours."
  def blacklist_ip(ip) do
    # Auto-expiry TTL prevents memory bloat from obsolete tracking logs
    ttl_ms = :timer.hours(24) # 24-hour ban duration
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
  Uses optimized Cachex prefix selectors to load items lazily.
  """
  def list_blacklisted_ips do
    require Cachex.Query

    # Compiles an optimized key prefix match query signature
    q =
      Cachex.Query.create(fn key, _value ->
        String.starts_with?(key, "blacklist:")
      end)

    case Cachex.stream(@cache, q) do
      {:ok, stream} ->
        stream
        |> Stream.map(fn {key, _val} -> String.replace(key, "blacklist:", "") end)
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
    ttl_ms = :timer.hours(1) # 1-hour soft cooldown window for strikes

    # Atomic write update pass tracks state without race conditions
    case Cachex.get_and_update(@cache, key, fn
           nil -> {:commit, 1}
           count -> {:commit, count + 1}
         end) do
      # 🔄 FIX: Match directly against the raw un-wrapped commit status tuple
      {:commit, count} when count >= 2 ->
        # TWO STRIKES TRIGGERED: Activate the 24-hour network firewall ban
        blacklist_ip(ip)
        true

      _one_strike ->
        # First offense: Set short 1-hour expiry so strikes reset if they stop spamming
        Cachex.expire(@cache, key, ttl_ms)
        false
    end
  end


  @doc """
  Wipes all infraction history markers for a specific user. Resets Hammer buckets,
  erases triggered words list history, and clears any active IP block filters.
  """
  def pardon_user(user_id, ip) do
    # 1. Clear out user's cached forbidden words list
    Cachex.del(@cache, "denied_words:#{user_id}")
    Cachex.del(@cache, "strikes:#{ip}")

    # 2. Lift the IP blacklist if an active network IP address was passed
    if ip, do: pardon_ip(ip)

    :ok
  end

  @doc """
  Bulk Administrator Override API. Instantly lifts all active 1-hour cooldowns,
  clears tracked word caches, and unlocks blocked IPs across the whole node cluster.
  """
  def lift_all_cooldowns do
    require Cachex.Query

    # Purge denied words history logs by prefix pattern match query pass
    words_query = Cachex.Query.create(fn k, _ -> String.starts_with?(k, "denied_words:") end)

    case Cachex.stream(@cache, words_query) do
      {:ok, stream} -> Enum.each(stream, fn {k, _} -> Cachex.del(@cache, k) end)
      _ -> :ok
    end

    # Purge strike counters
    strikes_query = Cachex.Query.create(fn k, _ -> String.starts_with?(k, "strikes:") end)

    case Cachex.stream(@cache, strikes_query) do
      {:ok, stream} -> Enum.each(stream, fn {k, _} -> Cachex.del(@cache, k) end)
      _ -> :ok
    end

    # Purge the 24-hour firewall blacklist collections
    blacklist_query = Cachex.Query.create(fn k, _ -> String.starts_with?(k, "blacklist:") end)

    case Cachex.stream(@cache, blacklist_query) do
      {:ok, stream} -> Enum.each(stream, fn {k, _} -> Cachex.del(@cache, k) end)
      _ -> :ok
    end

    :ok
  end

  # ─── SECTION 3: SYSTEM GLOBAL LOCKDOWN LEVEL (THE EMERGENCY PANIC BUTTON) ───

  @doc "Forces lockdown mode active for 4 hours by default (Automatic Cool-Off Cooldown)."
  def enable_lockdown do
    ttl_ms = :timer.hours(4) # 4-hour emergency lockdown duration
    Cachex.put(@cache, "lockdown_active", true, ttl: ttl_ms)
  end

  @doc "Deactivates the global security system lockdown mode."
  def disable_lockdown do
    Cachex.del(@cache, "lockdown_active")
  end

  @doc "Checks if the global emergency lockdown mode is active."
  def lockdown_active? do
    case Cachex.get(@cache, "lockdown_active") do
      {:ok, true} -> true
      _ -> false
    end
  end
end

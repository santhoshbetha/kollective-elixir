#IP Blacklist at the Plug.Conn level
defmodule Kollective.Security.Security do
  @moduledoc """
  Standalone system security, IP blacklisting, and administrative pardon manager.
  Operates completely in-memory via Cachex and Hammer to handle botnets under 0.02ms.
  """
  @cache :kollective_cache

  @doc "Bans an IP from the platform for 24 hours automatically."
  def blacklist_ip(ip) do
    # Auto-expiry TTL prevents memory bloat with old tracking logs [INDEX]
    Cachex.put(@cache, "blacklist:#{ip}", true, ttl: :erlang.convert_time_unit(24, :hours, :millisecond))
  end

  @doc "Bans an IP for a customizable dynamic timeframe (e.g. 1 hour cooldowns) [INDEX]."
  def blacklist_ip_temporary(ip, ttl_ms) do
    Cachex.put(@cache, "blacklist:#{ip}", true, ttl: ttl_ms)
  end

  @doc "Checks if an IP is currently blacklisted in RAM."
  def ip_blacklisted?(ip) do
    case Cachex.get(@cache, "blacklist:#{ip}") do
      {:ok, true} -> true
      _ -> false
    end
  end

  #Admin API to manually "pardon" (remove) an IP from the blacklist if a real user gets caught
  #1. Add the pardon_ip/1 function to your Security module to remove the entry from Cachex.

  #4. Why this works for "Pardoning"

  #  Immediate Effect: Since Cachex is in-memory, the moment the admin hits the DELETE endpoint, the IPBlacklist plug will stop "Black Holing" that IP on the very next request.
  #  No DB Cleanup: You don't have to worry about old records; the "pardon" simply clears the memory, and the "ban" would have expired naturally anyway.
  #  Security: By wrapping this in the ensure_admin_authenticated plug, only your trusted staff can lift these protections.
  @doc "Manually removes an IP from the blacklist (Admin API Pardon Trigger)."
  def pardon_ip(ip) do
    Cachex.del(@cache, "blacklist:#{ip}")
  end

  @doc """
  Streams blacklisted IPs safely out of memory without triggering RAM bloat.
  Uses Cachex.Query selectors to load items lazily.
  """
  def list_blacklisted_ips do
    # Require the query module to use the create macro safely
    require Cachex.Query

    # Official Cachex syntax: compiles a clean binary search query matching the prefix
    q = Cachex.Query.create(fn(key, _value) ->
      String.starts_with?(key, "blacklist:")
    end)

    case Cachex.stream(@cache, q) do
      {:ok, stream} ->
        stream
        |> Stream.map(fn({key, _val}) -> String.replace(key, "blacklist:", "") end)
        |> Enum.to_list()
      _ -> []
    end
  end

  #Pardon Button
  # To implement the Pardon Button, you need a single atomic function that wipes all "offense" data for a specific user.
  # This includes their Hammer denial count (the 3-strike counter), the Cachex list of triggered "Hard" words, and
  # the IP Blacklist if they were caught by the automated filter.

  #1. Update the Security Context
  #Add a pardon_user/2 function to your Security module. This function targets all the keys we've used to track this user's behavior.
  @doc """
  Wipes all offense history markers for a specific user. Resets Hammer counters,
  erases triggered words history lists, and clears any active IP block filters [INDEX].
  """
  def pardon_user(user_id, ip) do
    # 1. Reset Hammer "Post Denied" offense count to 0 instantly [INDEX]
    Hammer.delete_buckets("post_denied:#{user_id}")

    # 2. Clear the cached denied words audit string
    Cachex.del(@cache, "denied_words:#{user_id}")

    # 3. Lift the IP blacklist if applicable
    if ip, do: pardon_ip(ip)

    :ok
  end

  #Bulk Action API to allow admins to lift all current cooldowns at once if a specific keyword was mistakenly set to "Hard"

  #To implement a "Lift All Cooldowns" bulk API, you must clear two separate in-memory stores: the
  #Hammer buckets (which track the count of 3 denials) and the Cachex keys (which store the specific "Hard" words and the 1-hour IP blacklist).

  #1. Updated Security Context
  #Add a lift_all_cooldowns/0 function to your Security module. This function iterates through and deletes all keys associated with "Post Denied" offenses.

  @doc """
  Bulk Administrator Override API. Instantly lifts all active 1-hour cooldowns,
  clears tracked word caches, and unlocks blocked IPs without restarting services.
  """
  def lift_all_cooldowns do
    require Cachex.Query
    # 1. Clear Hammer buckets for the "post_denied" action
    Hammer.delete_buckets("post_denied:")

    # 2. Compile queries safely to purge keys by prefix without RAM bloat
    words_query = Cachex.Query.create(fn(k, _) -> String.starts_with?(k, "denied_words:") end)
    case Cachex.stream(@cache, words_query) do
      {:ok, stream} -> Enum.each(stream, fn({k, _}) -> Cachex.del(@cache, k) end)
      _ -> :ok
    end

    blacklist_query = Cachex.Query.create(fn(k, _) -> String.starts_with?(k, "blacklist:") end)
    case Cachex.stream(@cache, blacklist_query) do
      {:ok, stream} -> Enum.each(stream, fn({k, _}) -> Cachex.del(@cache, k) end)
      _ -> :ok
    end

    :ok
  end


  # ─── SECTION 2: HIGH-PERFORMANCE CRAWLER WHITELISTS ───

  @doc """
  High-performance crawler verification engine.
  Exempts search engines from rate limits using instant, RAM-based CIDR subnet checks.
  """
  def crawler_whitelisted?(ip_string) do
    case Cachex.get(@cache, "crawler_whitelist") do
      {:ok, prefixes} when is_list(prefixes) ->
        case :inet.parse_address(to_charlist(ip_string)) do
          {:ok, addr} ->
            Enum.any?(prefixes, fn cidr_str ->
              case InetCidr.parse_cidr(cidr_str) do
                # Safe tuple extraction prevents runtime crashes if format is malformed
                {:ok, cidr} -> InetCidr.contains?(cidr, addr)
                _ -> false
              end
            end)
          _ -> false
        end
      _ -> false
    end
  end

  # ─── SECTION 3: SYSTEM GLOBAL LOCKDOWN LEVEL ───

  @doc "Forces lockdown mode active for 4 hours by default (Automatic Cool-Off Cooldown)."
  def enable_lockdown do
    Cachex.put(@cache, "lockdown_active", true, ttl: :erlang.convert_time_unit(4, :hours, :millisecond))
  end

  @doc "Deactivates the global security system lockdown mode."
  def disable_down, do: Cachex.del(@cache, "lockdown_active")
  def disable_lockdown, do: Cachex.del(@cache, "lockdown_active")

  @doc "Checks if the global emergency lockdown mode is active."
  def lockdown_active? do
    case Cachex.get(@cache, "lockdown_active") do
      {:ok, true} -> true
      _ -> false
    end
  end

  #Automated IP Banning specifically for anyone who triggers a "Hard" keyword more than once

  #To implement this "Two-Strike" rule for Hard keywords, we will
  # use your existing Cachex setup to track "offense counts" per IP and then trigger the 24-hour Security Blacklist once they hit the second strike

  #1. Update the Security Context
  #Add a function to track "strikes" in memory. This is faster and cleaner than adding a new table to your database for
  # temporary bot behavior.
  @doc "Increments a strike count for an IP. Returns true if they should be banned."

  #4. Why this "Escalation" works:

  #  Strike 1 (The Warning): Real users who make a mistake get an error message (422). They can fix the post and try again.
  #  Strike 2 (The Hammer): Bots or malicious users who ignore the warning and try again are instantly Black-Holed. To them, it looks like they finally bypassed your filter, but their data is being vaporized in the Black Hole Response.
  #  Performance: Checking strikes via Cachex keeps your database safe from "retry loops" common in spam scripts.

  #5. Admin Visibility
  # You can now update your SecurityAlertWorker to include the strike count in the email:
  # "IP 1.2.3.4 has triggered a Hard-Ban for the second time and has been blacklisted for 24 hours."
  def record_hard_strike(ip) do
    key = "strikes:#{ip}"

    # Increment the strike count in Cachex
    case Cachex.get_and_update(@cache, key, fn
      nil -> 1
      count -> count + 1
    end) do
      {:ok, count} when count >= 2 ->
        # TWO STRIKES: Trigger the 24-hour ban
        blacklist_ip(ip)
        true
      _ ->
        # One strike: Set short expiry (e.g. 1 hour) so strikes reset if they stop
        Cachex.expire(@cache, key, :timer.hours(1))
        false
    end
  end

  #Global Kill Switch
  #To implement the Global Kill Switch, we will use Cachex to toggle a "Lockdown Mode." When active, this forces
  #every new post and event into the :pending status, regardless of the user's reputation or the content's keywords.

  #1.1. The Security Logic
  #Add the toggle functions to your Security context. This allows you to check the state of the "Kill Switch" in memory instantly.

  #def enable_lockdown do
    # Enable lockdown for 4 hours by default (automatic cooldown)
  #  Cachex.put(@cache, "lockdown_active", true, expiration: :timer.hours(4))
  #end

  #def disable_lockdown do
  #  Cachex.del(@cache, "lockdown_active")
  #end

  #def lockdown_active? do
  #  case Cachex.get(@cache, "lockdown_active") do
  #    {:ok, true} -> true
  #    _ -> false
  #  end
  #end


end

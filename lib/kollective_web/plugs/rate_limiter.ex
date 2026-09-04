# lib/kollective_web/plugs/rate_limiter.ex
defmodule KollectiveWeb.Plugs.RateLimiter do
  @moduledoc """
  High-Performance Memory Firewall & Sliding-Window Rate Limiter.
  Intercepts traffic, isolates bots using honey-pot "Black Hole" fake creations,
  and shields the PostgreSQL database transaction pool from connection stress.
  """
  import Plug.Conn
  require Logger

  alias Kollective.Security.Security

  # Configurable sliding-window limits matching your system profiles
  # 1 minute sliding window
  @time_window_ms 60_000
  # Max clicks allowed inside the window for a human
  @max_allowed_requests 5
  # 20+ hits inside a minute marks them as a malicious script
  @bot_threshold_count 20

  # Allow the action prefix to be configured per route plug declaration
  def init(opts) do
    Keyword.get(opts, :action, "default_action")
  end

  def call(conn, action_prefix) do
    # Identify by User ID if logged in, otherwise default to the client IP address
    user = conn.assigns[:current_user]

    # SYSTEM EXEMPTION: Administrators and moderators bypass rate limits entirely
    if user && (user.is_admin || user.is_moderator) do
      conn
    else
      check_limit(conn, user, action_prefix)
    end
  end

  # ─── SECTION 1: TIERED SYSTEM DEFENSE GATEWAY ───
  defp check_limit(conn, user, action_prefix) do
    ip = guest_ip(conn)
    id = if user, do: "user:#{user.id}", else: "ip:#{ip}"

    cond do
      # TIER 1: IN-MEMORY FIREWALL BLACKLIST PRE-CHECK
      # Short-circuits instantly if this unauthenticated IP is already blacklisted in Cachex
      is_nil(user) and Security.ip_blacklisted?(ip) ->
        log_aggressive_spam(id, "BLACKLISTED_IP_MATCH")
        black_hole_response(conn)

      # TIER 2: SEARCH ENGINE CRAWLER WHITELISTS
      # Verified search bots, index scrapers, or internal nodes bypass restriction limits entirely
      is_nil(user) and crawler_whitelisted?(ip) ->
        conn

      # TIER 3: SLIDING-WINDOW PERFORMANCE EVALUATION
      # Fallback to structural Hammer counting metrics execution
      true ->
        perform_hammer_check(conn, id, ip, user, action_prefix)
    end
  end

  # ─── SECTION 2: SLIDING-WINDOW ACCUMULATOR CHECKS ───

  defp perform_hammer_check(conn, id, ip, user, action_prefix) do
    # 🟢 FIXED: The metric bucket is now fully contextualized by route type
    bucket_key = "#{action_prefix}:#{id}"

    case Hammer.check_rate(bucket_key, @time_window_ms, @max_allowed_requests) do
      {:allow, _count} ->
        # Request is clean; return the connection to continue the pipeline execution
        conn

      {:deny, _limit} ->
        # Use read-only inspect_bucket to check how aggressively they are hammering
        case Hammer.inspect_bucket(bucket_key, @time_window_ms, @max_allowed_requests) do
          # FIX: Added the 5th variable element to perfectly match Hammer's native return signature
          {:ok, {count, _limit, _remaining, _ms_to_expiry, _created_at}}
          when count >= @bot_threshold_count ->
            # 1. Flag them as a script/bot and lock their IP inside Cachex in memory
            if is_nil(user), do: Security.blacklist_ip(ip)

            log_aggressive_spam(id, count)

            # 2. Return a FAKE SUCCESS to drop their traffic without letting them know
            black_hole_response(conn)

          _fallback_error ->
            log_rate_limit_trigger(id, conn)
            render_standard_rate_limit_error(conn)
        end
    end
  end

  # ─── SECTION 3: THE STRATEGIC BLACK-HOLE HONEY-POT TRAP ───

  defp black_hole_response(conn) do
    # Simulate realistic DB write latency (50ms to 200ms) to trick the script
    Process.sleep(Enum.random(50..200))

    response_payload = %{
      status: "success",
      data: %{
        id: "post_#{System.system_time(:millisecond)}",
        status: "published",
        # Lie to the bot to keep them trapped
        message: "Post created successfully."
      }
    }

    # Encode to JSON string in RAM and halt the request immediately
    # It never reaches your database and consumes zero processing cycles on controllers!
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(201, Jason.encode!(response_payload))
    |> halt()
  end

  # --- Structural Helper Utilities ---

  defp crawler_whitelisted?(ip_string) do
    case Cachex.get(:kollective_cache, "crawler_whitelist") do
      {:ok, prefixes} when is_list(prefixes) ->
        case :inet.parse_address(to_charlist(ip_string)) do
          {:ok, addr} ->
            Enum.any?(prefixes, fn cidr_str ->
              case InetCidr.parse_cidr(cidr_str) do
                {:ok, cidr} -> InetCidr.contains?(cidr, addr)
                _ -> false
              end
            end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp guest_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp render_standard_rate_limit_error(conn) do
    response_payload = %{
      status: "error",
      code: "rate_limit_exceeded",
      message: "Slow down! You are posting too fast."
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(response_payload))
    |> halt()
  end

  defp log_rate_limit_trigger(id, conn) do
    Logger.warning(
      "RATE_LIMIT_TRIGGERED: id=#{id} path=#{conn.request_path} ip=#{guest_ip(conn)}"
    )
  end

  defp log_aggressive_spam(id, count) do
    Logger.error("AGGRESSIVE_SPAM_DETECTED: id=#{id} attempts=#{count}")
  end
end

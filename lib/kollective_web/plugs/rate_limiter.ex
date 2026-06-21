# Rate-Limit Plug
#Create a Plug that you can drop into your router. This will block users (by IP or User ID) if they post too frequently
#(e.g., more than 5 posts per minute).
defmodule KollectiveWeb.Plugs.RateLimiter do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  alias Kollective.Security.Security

  # Configurable limits matching your system profiles
  @time_window_ms 60_000 # 1 minute
  @max_allowed_requests 5 # Max clicks inside window
  @bot_threshold_count 20 # 20+ hits inside a minute marks them as a bot

  def init(opts), do: opts

  def call(conn, _opts) do
    # Identify by User ID if logged in, otherwise by IP
    user = conn.assigns[:current_user]

    # EXEMPTION: If user is an admin, skip rate limiting
    if user && user.role == :admin do
      conn
    else
      check_limit(conn, user)
    end
  end

  @doc """
  Unified rate-limiting entry point. Intercepts incoming connections,
  evaluates reputation criteria, updates bucket states, and locks down abusers.
  """
  #2. Advanced: Tracking "Repeat Offenders" (call below from above for repeat offenders)
  #Why use inspect_bucket here?

  #  check_rate increments the counter. You only want to do this once per request.
  #  inspect_bucket is "read-only." It lets you look at the current state of that user's "punishment" without adding more time or hits to their limit.
  #  Thresholding: A human might click "Post" 6 or 7 times out of frustration. A bot will hit it 100 times a second. inspect_bucket helps you tell the difference.
  #defp check_limit2(conn, user) do

  #3. IP Blacklist at the Plug.Conn level
  # above plus IP Blacklist check

  # Why this is the "Ultimate" Defense:

  #  Zero DB Pressure: By using Cachex, the check happens in RAM. Even a massive botnet won't slow down your PostgreSQL database.
  #  The "Silent" Treatment: The bot continues to get 201 Created via the black_hole_response, so it doesn't know it's being blocked by the IP filter.
  #  Auto-Expiry: Since Cachex handles the TTL (Time To Live), the ban naturally lifts after 24 hours, so you don't have to manually manage a massive list of old IPs.
  #  defp check_limit3(conn, user) do
  def check_limit(conn, user) do
    ip = guest_ip(conn)
    id = if user, do: "user:#{user.id}", else: "ip:#{ip}"

    cond do
      # TIER 1: IN-MEMORY BLACKLIST PRE-CHECK
      # Short-circuits instantly if this unauthenticated IP is already blacklisted in Cachex
      is_nil(user) and Security.ip_blacklisted?(ip) ->
        log_aggressive_spam(id, "BLACKLISTED_IP_MATCH")
        black_hole_response(conn)

      # TIER 2: WHITELIST CRITERIA CHECK
      # Safe search bots, scrapers, or internal tools bypass restriction counters entirely
      is_nil(user) and crawler_whitelisted?(ip) ->
        conn

      # TIER 3: SLIDING-WINDOW PERFORMANCE EVALUATION
      # Fallback to structural Hammer counting metrics execution
      true ->
        perform_hammer_check(conn, id, ip, user)
    end
  end

  defp perform_hammer_check(conn, id, ip, user) do
    # Create a unique action bucket namespace based on the route or function context
    bucket_key = "create_post:#{id}"

    case Hammer.check_rate(bucket_key, @time_window_ms, @max_allowed_requests) do
      {:allow, _count} ->
        # Request is clean; return the connection to continue the pipeline execution
        conn

      {:deny, _limit} ->
        # Use read-only inspect_bucket to check how aggressively they are hammering
        case Hammer.inspect_bucket(bucket_key, @time_window_ms, @max_allowed_requests) do
        # FIX: Added a 5th element to match the actual return signature of Hammer.inspect_bucket/3
        {:ok, {count, _limit, _remaining, _created_at, _expires_at}} when count >= @bot_threshold_count ->
          # 1. Flag them as a script/bot and lock their IP inside Cachex in memory
          if is_nil(user), do: Security.blacklist_ip(ip)

            log_aggressive_spam(id, count)

            # 2. Return a FAKE SUCCESS to drop their traffic without letting them know [INDEX, INDEX]
            black_hole_response(conn)

          {:ok, _} ->
            # Standard human frustration clicking; log it and send a standard 422/429 halt
            log_rate_limit_trigger(id, conn)
            render_standard_rate_limit_error(conn)

          _ ->
            # Fallback wrapper if bucket inspect fails
            render_standard_rate_limit_error(conn)
        end
    end
  end

  #To implement a high-performance whitelist for official search engine crawlers
  #3. Update the RateLimiter Plug
  # Now, instead of slow DNS lookups, the plug performs a fast memory-based CIDR check.

  # Keyset CIDR Crawler Whitelist Validator
  defp crawler_whitelisted?(ip_string) do
    # Pull the pre-loaded IP range prefixes from your shared Cachex memory block
    case Cachex.get(:kollective_cache, "crawler_whitelist") do
      {:ok, prefixes} when is_list(prefixes) ->
        # Convert incoming string string IP to the tuple format required by InetCidr
        case :inet.parse_address(to_charlist(ip_string)) do
          {:ok, addr} ->
            Enum.any?(prefixes, fn cidr_str ->
              # Explicitly match on a successful parse to avoid syntax crashes if CIDR data format breaks
              case InetCidr.parse_cidr(cidr_str) do
                {:ok, cidr} -> InetCidr.contains?(cidr, addr)
                _ -> false
              end
            end)

          _ ->
            false
        end

      _ ->
        false # Default to False if cache is empty or missing
    end
  end

  defp render_standard_rate_limit_error(conn) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{error: "Slow down! You are posting too fast."})
    |> halt()
  end


  #"Fake Success" logic to the RateLimiter so that aggressive bots
  #receive a 200 OK but their data is simply discarded (dropped) instead of being saved at all

  #"Black Hole" rate limiter, you modify the Plug to stop processing the request (halting) but return a 200 OK or 201 Created JSON response
  #instead of an error. The data is effectively "dropped" before it ever reaches your database or your PostController.

  #2. Why the halt() is critical
    # The halt(conn) function tells Phoenix: "Do not pass this request to the next plug or the controller."

    # Result: Your database never sees the post. Your Posts.create_post/2 function is never called. No CPU time is wasted processing the spam content.
    # Bot's perspective: It receives a standard JSON response that looks identical to a successful post.

  #3. The "Infinite Loop" Trap
   # Because the bot thinks it is succeeding, it will likely keep using the same account and the same IP. This makes it easier for you to:

    #Keep them "trapped" in the Black Hole.
    #Gather their IP addresses for a permanent firewall block later.
    #Prevent them from "rotating" to a new account (which they would do if they saw a 429 Too Many Requests or a 403 Forbidden).

  #4. Advanced: Randomized Delay
     # To make the "Black Hole" even more convincing, you can add a tiny, random sleep so the response time looks like a
     #real database write.

  #User Type	                                    Action	                                         Result
  #Real User	                                   Normal Post	                              Saved as published.
  #Shadow-Banned                                User	Normal Post	                  Saved as pending (Hidden), but API says published.
  #Frustrated                                  Human	6th Post/min	                Blocked with 429 Too Many Requests.
  #Aggressive Bot	                               21st+ Post/min	               Black Holed: API says 201 Created, but data is discarded.
  defp black_hole_response(conn) do
    # Simulate DB latency (50ms to 200ms)
    Process.sleep(Enum.random(50..200))
    # THE FAKE SUCCESS TREATMENTS: Continues to mimic a valid Mastodon JSON creation footprint
    # Spammers will keep running their scripts blindly, unaware that their data is being discarded
    conn
    |> put_status(:created) # Fake 201 status
    |> json(%{
      data: %{
        id: "fake-#{:os.system_time(:millisecond)}",
        status: "published",
        message: "Post created successfully" # Lie to the bot
      }
    })
    |> halt() # Stop the request here so it NEVER hits the Controller/DB
  end

  defp guest_ip(conn) do
    # Extract client IP, handling proxies correctly
    conn.remote_ip |> :inet.ntoa() |> to_string()
    #conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
  end

  defp log_rate_limit_trigger(id, conn) do
    path = conn.request_path

    # 1. System Log (Great for monitoring tools like Grafana/Loki)
    Logger.warning("RATE_LIMIT_TRIGGERED: id=#{id} path=#{path} ip=#{guest_ip(conn)}")

    # 2. Database Log (Optional: if you want admins to see this in their dashboard)
    # Kollective.Moderation.log_system_event(%{
    #   action: "rate_limit_exceeded",
    #   target: id,
    #   details: "User attempted to post more than 5 times per minute"
    # })
  end

  defp log_aggressive_spam(id, count) do
    Logger.error("AGGRESSIVE_SPAM_DETECTED: id=#{id} attempts=#{count}")
    # Optional: Trigger an automated shadow-ban or IP block here
  end

end

#2. Why this is the best approach:

#    Performance: The admin check happens before any hit to the Hammer backend (ETS/Redis), saving processing time for your staff.
#    Flexibility: You can expand this logic to give "Verified" users higher limits (e.g., 20 posts/min) while keeping "New" users on the strict limit.
#    Security: By using the remote_ip as a fallback, you prevent unauthenticated bots from flooding the API even before they create an account.

#3. Verification in IEx
#You can manually clear a rate limit for a specific user if they get blocked by mistake:
# Clear a specific user's limit in IEx
#Hammer.delete_buckets("create_post:user:123")

#########################################################################################
# log these rate-limit triggers so you can identify which IPs are trying to spam your keywords
# Advanced: Tracking "Repeat Offenders"
#If you want to automatically Shadow-ban the IP of anyone who triggers the rate limit multiple times, you can check the hit count:
# Inside your rate limiter logic
#case Hammer.inspect_bucket("create_post:#{id}", 60_000, 5) do
#  {:ok, {count, _limit, _remaining, _expiry}} when count > 20 ->
    # This user has tried 20+ times while being blocked.
    # Flag them for manual admin review.
#    Kollective.Accounts.flag_user_for_spam(id)
#  _ -> :ok
#end

#3. Monitoring via Telemetry
#Since you already have PromEx in your children list, you can emit a telemetry event to see "Rate Limit Hits"
#on your Grafana dashboard.

# :telemetry.execute([:kollective, :api, :rate_limit], %{count: 1}, %{user_id: id})

#Why Log This?

#    Identify Botnets: If 100 different IPs from the same subnet hit the limit simultaneously, you know you're under a coordinated attack.
#    Adjust Thresholds: If your most active (real) users are hitting the limit, you'll see the logs and know it's time to increase the "5 posts per minute" limit to 10.
#    Security Context: When an admin reviews a "Pending" post from the shadow-ban, they can check if that same user was also triggering rate-limit alerts.

defmodule Kollective.Moderation.RateLimiterPlug do
  require Logger

  @doc """
  🔒 IN-MEMORY TOKEN BUCKET FILTER
  Enforces a strict threshold of 5 incoming message actions per 10-second rolling window.
  """
  def check_ingress_throttle(user_id) do
    cache_key = "throttle:msg:#{user_id}"
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    # We read/write directly from local high-speed Cachex memory tables [INDEX]
    # Ensure {:cachex, "~> 3.6"} is active inside your mix.exs dependencies
    case Cachex.get(:kollective_runtime_cache, cache_key) do
      {:ok, nil} ->
        # If the bucket is blank, provision a fresh 10-second throttle profile tracker
        initial_bucket = %{tokens: 4, last_updated: now_unix}
        Cachex.put(:kollective_runtime_cache, cache_key, initial_bucket, ttl: :timer.seconds(10))
        :allow_ingress

      {:ok, bucket} ->
        # Calculate how many tokens have naturally regenerated since the user's last action
        seconds_passed = max(0, now_unix - bucket.last_updated)
        # Restores 1 token token every 2 seconds
        regenerated_tokens = div(seconds_passed, 2)

        current_tokens = min(5, bucket.tokens + regenerated_tokens)

        if current_tokens > 0 do
          # Consume 1 token and commit the updated tracking map down to memory
          updated_bucket = %{tokens: current_tokens - 1, last_updated: now_unix}

          Cachex.put(:kollective_runtime_cache, cache_key, updated_bucket,
            ttl: :timer.seconds(10)
          )

          :allow_ingress
        else
          Logger.warning("⚠️ [RATE LIMIT TRIP]: Request throttled for user account ##{user_id}")
          {:throttled_lockout, 10 - seconds_passed}
        end
    end
  end
end

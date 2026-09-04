# lib/kollective/civic/vouch_cache.ex
defmodule Kollective.Civic.VouchCache do
  @moduledoc """
  High-performance caching layer using Cachex. Bypasses cluster bottlenecks
  by utilizing localized lookups with automated TTL sweeps.
  """
  @cache_name :vouch_secure_tokens
  @ttl_seconds 60

  import Ecto.Query

  alias Kollective.Repo
  alias Kollective.Civic.TokenSchema

  @doc """
  Generates a cryptographically secure, single-use token valid for 60 seconds.
  """
  def generate_token(user_id) do
    secure_token =
      "vouch_tmp_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    expires_at =
      DateTime.add(DateTime.utc_now(), @ttl_seconds, :second) |> DateTime.truncate(:second)

    # 1. Write to Postgres immediately so all nodes can see it
    %TokenSchema{token: secure_token, user_id: user_id, expires_at: expires_at}
    |> Repo.insert!()

    # 2. Cache it locally on THIS node for speed
    Cachex.put(@cache_name, secure_token, user_id, ttl: :timer.seconds(@ttl_seconds))

    secure_token
  end

  @doc """
  Validates a token payload string. If valid, consumes it instantly (Single-Use Guard)
  and returns the associated target user ID.
  """
  def consume_token(token) do
    # 1. Check local Cachex memory first (Fast Path)
    case Cachex.take(@cache_name, token) do
      {:ok, user_id} when not is_nil(user_id) ->
        # Define the query payload cleanly
        delete_query = from(t in TokenSchema, where: t.token == ^token)

        # 🚀 FIX: Execute synchronously in testing to protect the Ecto Sandbox connection pool.
        # Spawns an unlinked asynchronous background task safely in production only.
        if Mix.env() == :test do
          Repo.delete_all(delete_query)
        else
          Task.start(fn -> Repo.delete_all(delete_query) end)
        end

        {:ok, user_id}

      _fallback ->
        # 2. Slow Path: Fetch from Postgres and delete it atomically using a database transaction.
        Repo.transaction(fn ->
          case Repo.get_by(TokenSchema, token: token) do
            %TokenSchema{user_id: user_id, expires_at: expires_at} ->
              from(t in TokenSchema, where: t.token == ^token) |> Repo.delete_all()

              if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
                user_id
              else
                # FIX: Normalized error atom naming strings to avoid mismatching controller guards
                Repo.rollback(:token_expired)
              end

            nil ->
              Repo.rollback(:token_invalid)
          end
        end)
        |> case do
          {:ok, user_id} -> {:ok, user_id}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end

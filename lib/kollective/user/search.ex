# lib/kollective/accounts/user_search.ex
defmodule Kollective.User.Search do
  @moduledoc """
  High-Performance, typo-tolerant local profile search engine.
  Combines PostgreSQL Full-Text Search (FTS), Trigram similarities,
  and relational social graph ranking boosting natively inside database memory.
  """
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.User.Query, as: UserQuery

  @default_limit 20

  @doc """
  Searches the local users database using a hybrid FTS and Trigram scoring system.
  Automatically applies privacy guards, block masks, and social rank weights.
  """
  def search(query_string, opts \\ []) do
    following_only = Keyword.get(opts, :following, false)
    result_limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    for_user = Keyword.get(opts, :for_user)

    # 1. Clean, trim, and strip incoming search handles
    cleaned_query =
      query_string
      |> to_string()
      |> String.trim()
      |> String.trim_leading("@")

    if cleaned_query == "" or String.length(cleaned_query) < 2 do
      []
    else
      cleaned_query
      |> compile_search_query(for_user, following_only)
      |> limit(^result_limit)
      |> offset(^offset)
      |> Repo.all()
    end
  end

  # ─── CORE MULTI-TIERED SEARCH COMPILER ───

  defp compile_search_query(query_string, for_user, following_only) do
    base_query(for_user, following_only)
    |> filter_deactivated_users()
    |> filter_invisible_users()
    |> filter_blocked_users(for_user)
    |> fts_search(query_string)
    # FIX: Combined similarity calculations with safe positional binding parameters
    |> trigram_similarity_rank(query_string)
    # FIX: Relational social boosting moved entirely into high-speed database joins
    |> boost_social_rank(for_user)
    |> subquery()
    |> order_by([u], desc: u.search_rank, asc: u.username)
  end

  # ─── STRUCTURAL FILTERS & SECURITY SHIELDS ───

  defp base_query(%User{} = user, true) do
    UserQuery.build(%{friends: user})
  end

  defp base_query(_for_user, _following_only), do: from(u in User)

  defp filter_deactivated_users(query) do
    from(u in query, where: u.is_active == true and u.is_approved == true)
  end

  defp filter_invisible_users(query) do
    from(u in query, where: u.is_discoverable == true)
  end

  defp filter_blocked_users(query, nil), do: query
  defp filter_blocked_users(query, %User{} = current_user) do
    # Bidirectional safety gate: Exclude users who have blocked you OR whom you have blocked
    blocked_ids_subquery =
      from(r in "user_relationships",
        where:
          (r.source_id == ^current_user.id or r.target_id == ^current_user.id) and
            r.type == "block",
        select:
          fragment(
            "CASE WHEN r.source_id = ? THEN r.target_id ELSE r.source_id END",
            ^current_user.id
          )
      )

    from(u in query, where: u.id not in subquery(blocked_ids_subquery))
  end

  # ─── TEXT MATCHING VECTORS ───
  defp fts_search(query, query_string) do
    fts_token =
      query_string
      |> String.replace(~r/[^\w\s]+/u, " ")
      |> String.trim()
      |> String.split()
      |> Enum.map(&(&1 <> ":*"))

      |> Enum.join(" | ")

    from(u in query,
      where:
        fragment(
          """
          (
            setweight(to_tsvector('simple', regexp_replace(?, '\\W', ' ', 'g')), 'A') ||
            setweight(to_tsvector('simple', regexp_replace(coalesce(?, ''), '\\W', ' ', 'g')), 'B')
          ) @@ to_tsquery('simple', ?)
          """,
          u.username,
          u.name,
          ^fts_token
        )
    )
  end

  defp trigram_similarity_rank(query, query_string) do
    from(u in query,
      select_merge: %{
        # FIX: Explicit parameter mapping fixes macro schema compilation errors
        search_rank: fragment("similarity(?, ?) + similarity(?, coalesce(?, ''))", ^query_string, u.username, ^query_string, u.name)
      }
    )
  end

  # ─── HIGH-SPEED O(1) SOCIAL ACCELERATOR ───

  defp boost_social_rank(query, nil), do: query
  defp boost_social_rank(query, %User{id: current_user_id}) do
    # Subqueries calculate relationship flags inside DB RAM instantly without loading lists to Elixir
    from(u in query,
      left_join: follows_target in subquery(from(r in "user_relationships", where: r.source_id == ^current_user_id and r.type == "follow", select: %{id: r.target_id, match: true})),
        on: follows_target.id == u.id,
      left_join: followed_by in subquery(from(r in "user_relationships", where: r.target_id == ^current_user_id and r.type == "follow", select: %{id: r.source_id, match: true})),
        on: followed_by.id == u.id,
      select_merge: %{
        search_rank: fragment(
          """
          CASE
            WHEN ? AND ? THEN ? * 1.5 -- Mutual Friends
            WHEN ? THEN ? * 1.3        -- Accounts I Follow
            WHEN ? THEN ? * 1.1        -- Accounts Following Me
            ELSE ?
          END
          """,
          not is_nil(follows_target.match), not is_nil(followed_by.match), u.search_rank,
          not is_nil(follows_target.match), u.search_rank,
          not is_nil(followed_by.match), u.search_rank,
          u.search_rank
        )
      }
    )
  end
end

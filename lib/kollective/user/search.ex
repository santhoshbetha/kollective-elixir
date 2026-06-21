# lib/kollective/accounts/user_search.ex
defmodule Kollective.User.Search do
  @moduledoc """
  Fuzzy, typo-tolerant local profile search engine.
  Leverages PostgreSQL FTS and Trigram vector distances.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Accounts

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

    # 1. Clean, trim, and strip incoming search handles (e.g. "@alice" -> "alice")
    query_string =
      query_string
      |> to_string()
      |> String.trim()
      |> String.trim_leading("@")

    if query_string == "" or String.length(query_string) < 2 do
      []
    else
      query_string
      |> compile_search_query(for_user, following_only)
      |> limit(^result_limit)
      |> offset(^offset)
      |> Repo.all()
    end
  end

  # --- Core Multi-Tiered Search Compiler ---

  defp compile_search_query(query_string, for_user, following_only) do
    # 1. Start with the appropriate baseline target user group query
    base_query(for_user, following_only)
    # 2. Strict Standalone Isolation & Data Privacy Filters
    |> filter_deactivated_users()
    |> filter_invisible_users()
    |> filter_blocked_users(for_user)
    # 3. Text Density Matching: Core FTS Search Vector Matrix
    |> fts_search(query_string)
    # 4. Fuzzy Proximity Scoring: Trigram Distance Calculations (Typo Safety)
    |> trigram_similarity_rank(query_string)
    # 5. Relationship Boosts: Bubble up mutual friends and direct followers
    |> boost_social_rank(for_user)
    # Wrap in an operational subquery to execute sorting parameters cleanly
    |> subquery()
    |> order_by([u], desc: u.search_rank, asc: u.username)
  end

  # --- Structural Data Filters & Security Guards ---

  defp base_query(%User{} = user, true) do
    # Restrict lookup bounds to accounts the current user explicitly follows
    Kollective.User.Query.build(%{friends: user})
  end
  defp base_query(_for_user, _following_only), do: from(u in User)

  defp filter_deactivated_users(query) do
    from(u in query, where: u.is_active == true)
  end

  defp filter_invisible_users(query) do
    from(u in query, where: u.invisible == false)
  end

  defp filter_blocked_users(query, nil), do: query
  defp filter_blocked_users(query, %User{} = current_user) do
    # Bidirectional safety gate: Exclude users who have blocked you OR whom you have blocked
    blocked_ids_subquery =
      from(r in "user_relationships",
        where: (r.source_id == ^current_user.id or r.target_id == ^current_user.id) and r.type == "block",
        select: fragment("CASE WHEN r.source_id = ? THEN r.target_id ELSE r.source_id END", ^current_user.id)
      )

    from(u in query, where: u.id not in subquery(blocked_ids_subquery))
  end

  # --- Text Evaluation & Ranking Matrices ---

  defp fts_search(query, query_string) do
    # Format the input string into a standard PostgreSQL prefix wildcard query (e.g. "ali:*")
    fts_token =
      query_string
      |> String.replace(~r/[^\w\s]+/u, " ")
      |> String.trim()
      |> String.split()
      |> Enum.map(&(&1 <> ":*"))

      |> Enum.join(" | ")

    from(u in query,
      where: fragment(
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
        search_rank: fragment(
          "similarity(?, u.username) + similarity(?, coalesce(u.name, ''))",
          ^query_string,
          ^query_string
        )
      }
    )
  end

  defp boost_social_rank(query, nil), do: query
  defp boost_social_rank(query, %User{} = for_user) do
    # Fetch flat relationship integer tracking arrays using your optimized contexts
    friends_ids = Accounts.get_following_ids(for_user.id)

    # Query followers using a light standalone relational inline array extract query
    followers_ids = Repo.all(
      from(r in "user_relationships",
        where: r.target_id == ^for_user.id and r.type == "follow",
        select: r.source_id
      )
    )

    from(u in subquery(query),
      select_merge: %{
        search_rank: fragment(
          """
          CASE
            WHEN u.id IN (?) AND u.id IN (?) THEN u.search_rank * 1.5 -- Mutual Friends
            WHEN u.id IN (?) THEN u.search_rank * 1.3                 -- People I Follow
            WHEN u.id IN (?) THEN u.search_rank * 1.1                 -- My Followers
            ELSE u.search_rank
          END
          """,
          ^friends_ids, ^followers_ids,
          ^friends_ids,
          ^followers_ids
        )
      }
    )
  end
end

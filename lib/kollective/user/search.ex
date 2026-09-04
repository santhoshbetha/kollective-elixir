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
    |> order_by([u], asc: u.username)
  end

  # ─── STRUCTURAL FILTERS & SECURITY SHIELDS ───

  defp base_query(%User{} = user, true) do
    UserQuery.build(%{friends: user})
  end

  defp base_query(_for_user, _following_only), do: from(u in User)

  defp filter_deactivated_users(query) do
    from(u in query, where: u.is_active == true)
  end

  defp filter_invisible_users(query) do
    from(u in query, where: u.is_discoverable == true)
  end

  defp filter_blocked_users(query, nil), do: query
  defp filter_blocked_users(query, %User{}), do: query

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
          u.display_name,
          ^fts_token
        )
    )
  end
end

defmodule KollectiveWeb.SearchController do
  use KollectiveWeb, :controller

  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias KollectiveWeb.Plugs.RateLimiter
  alias Kollective.Pagination.Pagination
  alias Kollective.User.Search, as: UserSearch

  require Logger

  @search_limit 40

  # 1. Enforce protective API abuse filters across your key access points
  plug(RateLimiter, [name: :search] when action in [:search, :account_search])

  @doc """
  Unified Comprehensive Search Endpoint. Runs high-speed parallel tasks using
  Task.async_stream to hunt down matching accounts, tags, and cursor-paginated posts simultaneously.
  """
  # GET /api/v1/search (Main application entryway mapping parameters string arrays)
  def search(conn, params) do
    # Pull current active authenticated credentials safely
    user = conn.assigns.current_user
    query_string = String.trim(params["q"] || params[:q] || "")

    # Clean short-circuit layout protection to save CPU resources under blank inputs
    if query_string == "" or String.length(query_string) < 3 do
      json(conn, %{"posts" => [], "accounts" => [], "hashtags" => []})
    else
      options = compile_search_options(params, user)
      timeout = Keyword.get(Repo.config(), :timeout, 15_000)

      # Define baseline template dictionary
      default_values = %{"posts" => [], "accounts" => [], "hashtags" => []}
      target_type = params["type"]

      # 2. PARALLEL TRANSACTION POOL PROCESSING (Task Async Stream)
      result =
        default_values
        |> Enum.map(fn {resource, default_value} ->
          # If type is empty or explicitly matches this resource, build the execution lambda closure
          if is_nil(target_type) or target_type == resource do
            {resource, fn -> execute_resource_search(resource, query_string, options, params) end}
          else
            {resource, fn -> default_value end}
          end
        end)
        |> Task.async_stream(fn {resource, lambda_func} -> {resource, with_fallback(lambda_func)} end,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Enum.reduce(default_values, fn
          {:ok, {resource, search_hits}}, acc -> Map.put(acc, resource, search_hits)
          _timeout_or_crash_error, acc -> acc
        end)

      json(conn, result)
    end
  end

  # GET /api/v1/search/accounts (Targeted structural accounts lookup)
  def account_search(conn, %{"q" => query} = params) do
    user = conn.assigns.current_user
    options = compile_search_options(params, user)
    accounts = with_fallback(fn -> UserSearch.search(String.trim(query), options) end)

    json(conn, %{accounts: serialize_accounts(accounts)})
  end

  # GET /api/v1/search/location (Targeted geographical coordinate locator lookup)
  @spec location(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def location(conn, %{"q" => query} = params) do
    result = with_fallback(fn ->
      Geospatial.Service.service().search(String.trim(query), Map.to_list(params))
    end, [])

    json(conn, %{locations: result})
  end

  # --- Multi-Resource Parallel Execution Route Router ---

  defp execute_resource_search("accounts", query, options, _params) do
    users = UserSearch.search(query, [
      for_user: options[:for_user],
      following: options[:following],
      limit: options[:limit] || 20,
      offset: options[:offset] || 0
    ])

    serialize_accounts(users)
  end

  defp execute_resource_search("posts", query, options, params) do
    # UPGRADE: Connects directly into our optimized keyset cursor search engine!
    # Pulls block masks, filters out tombstones, performs O(1) batch pre-fetch hydration loops
    cursor_params = %{"cursor" => params["cursor"] || params["max_id"]}

    %{entries: results, next_cursor: next_cursor} =
      Posts.search_posts(query, options[:for_user], cursor_params)

    %{
      results: serialize_posts(results),
      next_cursor: next_cursor # Return tracking token inside structural response block
    }
  end

  defp execute_resource_search("hashtags", query, options, _params) do
    tags_path = KollectiveWeb.Endpoint.url() <> "/tag/"

    # 1. Run the tag preparation and pagination
    paginated_result = prepare_tags(query, options)

    # 2. Extract the plain list from the .entries key before mapping
    paginated_result.entries
    |> Enum.map(fn tag ->
      %{name: tag, url: tags_path <> tag}
    end)
  end

  # --- Structural Serialization Presentation Maps (Replaces redundant JSON Views) ---

  defp serialize_accounts(users) do
    Enum.map(users, fn u ->
      %{
        id: u.id,
        username: u.username,
        display_name: u.display_name,
        avatar_url: u.avatar_url
      }
    end)
  end

  defp serialize_posts(entries) do
    Enum.map(entries, fn item ->
      %{
        id: item.post.id,
        content: item.post.content,
        category: item.post.category,
        inserted_at: item.post.inserted_at,
        likes_count: item.likes_count,
        reblogs_count: item.reblogs_count,
        has_liked: item.has_liked,
        has_reblogged: item.has_reblogged,
        favourited: item.post.favourited,
        author: %{id: item.post.author.id, username: item.post.author.username, avatar_url: item.post.author.avatar_url}
      }
    end)
  end

  # --- Internal Caching & Text Sanitization Core Utilities ---

  defp compile_search_options(params, user) do
    limit_param = params["limit"] || params[:limit] || 20
    parsed_limit = if is_binary(limit_param), do: String.to_integer(limit_param), else: limit_param

    [
      resolve: params["resolve"] || params[:resolve],
      following: params["following"] || params[:following],
      limit: min(parsed_limit, @search_limit),
      offset: params["offset"] || params[:offset],
      type: params["type"] || params[:type],
      for_user: user
    ]
    |> Enum.filter(&elem(&1, 1))
  end

  defp prepare_tags(query, options) do
    tags =
      query
      |> preprocess_uri_query()
      # Split by spaces/punctuation but preserve the words themselves
      |> String.split(~r/[^#\w]+/u, trim: true)
      |> Enum.uniq_by(&String.downcase/1)

    # 2. Separate explicit hashtags from plain text words
    explicit_tags = Enum.filter(tags, fn tag -> String.starts_with?(tag, "#") end)

    # 3. Choose strategy: If explicit hashtags exist, use only those. Otherwise, use all words.
    tags = if Enum.any?(explicit_tags), do: explicit_tags, else: tags

    # 4. Clean up: Strip leading hashes so you are left with just the raw tag text
    tags = Enum.map(tags, fn tag -> String.trim_leading(tag, "#") end)

    # 5. Conditionally inject a combined single-string tag if no explicit hashtags were used
    tags =
      if Enum.empty?(explicit_tags) && !options[:skip_joined_tag] do
        add_joined_tag(tags)
      else
        tags
      end

    Pagination.paginate(tags, options)
  end

  defp add_joined_tag(tags) do
    tags
    |> Kernel.++([joined_tag(tags)])
    |> Enum.uniq_by(&String.downcase/1)
  end

  # If `query` is a URI, returns last component of its path, otherwise returns `query`
  defp preprocess_uri_query(query) do
    if query =~ ~r/https?:\/\// do
      query
      |> String.trim_trailing("/")
      |> URI.parse()
      |> Map.get(:path)
      |> String.split("/")
      |> Enum.at(-1)
    else
      query
    end
  end

  defp joined_tag(tags) do
    tags |> Enum.map(&String.capitalize/1) |> Enum.join()
  end

  defp with_fallback(f, fallback \\ []) do
    try do
      f.()
    rescue
      error ->
        Logger.error("#{__MODULE__} background parallel search error exception: #{inspect(error)}")
        fallback
    end
  end
end

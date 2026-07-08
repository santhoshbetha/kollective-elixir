# lib/kollective_web/controllers/search_controller.ex
defmodule KollectiveWeb.SearchController do
  use KollectiveWeb, :controller
  import Ecto.Query, only: [from: 2]

  alias Kollective.Repo
  alias Kollective.Posts.Posts
  alias Kollective.User.Search, as: UserSearch
  alias KollectiveWeb.PostJSON
  alias KollectiveWeb.AccountJSON

  require Logger

  @search_limit 40

  # 🛡️ Human Gate Firewall: Blocks scrapers and automated API abuse
  plug KollectiveWeb.Plugs.RateLimiter, [name: :search] when action in [:search, :account_search]

  @doc """
  Unified Comprehensive Search Entryway.
  Runs high-speed parallel operations over your resources concurrently inside server RAM .
  """
  # GET /api/v1/search?q=austin&type=posts
  def search(conn, params) do
    user = conn.assigns.current_user
    query_string = String.trim(params["q"] || params[:q] || "")

    if query_string == "" || String.length(query_string) < 3 do
      json(conn, %{"posts" => %{results: []}, "accounts" => [], "hashtags" => [], "events" => []})
    else
      options = compile_search_options(params, user)
      timeout = Keyword.get(Repo.config(), :timeout, 15_000)

      # 1. Expand standard templates to support your new grassroots "events" dashboard grid!
      default_values = %{"posts" => %{results: []}, "accounts" => [], "hashtags" => [], "events" => []}
      target_type = params["type"]

      result =
        default_values
        |> Enum.map(fn {resource, default_value} ->
          if is_nil(target_type) || target_type == resource do
            {resource, fn -> execute_resource_search(resource, query_string, options, params) end}
          else
            {resource, fn -> default_value end}
          end
        end)
        |> Task.async_stream(
          fn {resource, lambda_func} -> {resource, with_fallback(lambda_func, default_values[resource])} end,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Enum.reduce(default_values, fn
          {:ok, {resource, search_hits}}, acc -> Map.put(acc, resource, search_hits)
          _error, acc -> acc
        end)

      conn |> put_status(:ok) |> json(result)
    end
  end

  # GET /api/v1/search/accounts?q=alice
  def account_search(conn, %{"q" => query} = params) do
    user = conn.assigns.current_user
    options = compile_search_options(params, user)
    accounts = with_fallback(fn -> UserSearch.search(String.trim(query), options) end, [])

    json(conn, %{status: "success", accounts: AccountJSON.index(%{users: accounts})})
  end

  # ─── CORE RESOURCE ROUTING HANDSHAKES ───

  defp execute_resource_search("accounts", query, options, _params) do
    users = UserSearch.search(query, options)
    AccountJSON.index(%{users: users}) # Uniform serialization contract layout
  end

  defp execute_resource_search("posts", query, options, params) do
    cursor_params = %{"cursor" => params["cursor"] || params["max_id"]}

    %{entries: results, next_cursor: next_cursor} =
      Posts.search_posts(query, options[:for_user], cursor_params)

    %{
      results: PostJSON.index(%{entries: results}),
      next_cursor: next_cursor
    }
  end

  defp execute_resource_search("events", query, options, params) do
    # 📅 TARGETED GRASSROOTS ACTIONS SEARCH UPGRADE
    # Connects your dashboard searches straight into your geofenced actions engine
    scope_toggle = params["scope"] || "local"
    actions = Kollective.Events.Events.list_collective_actions(options[:for_user], "all", scope_toggle)

    # Filter text matches inside RAM for optimal sub-millisecond responsiveness
    filtered_actions = Enum.filter(actions, fn act ->
      String.contains?(String.downcase(act.name), String.downcase(query)) ||
      String.contains?(String.downcase(act.description || ""), String.downcase(query))
    end)

    Enum.map(filtered_actions, fn item ->
      %{
        id: to_string(item.id),
        name: item.name,
        category: item.category,
        start_time: Calendar.strftime(item.start_time, "%Y-%m-%dT%H:%M:%SZ"),
        location_name: item.location_name,
        is_official: not is_nil(item.organization_id)
      }
    end)
  end

  defp execute_resource_search("hashtags", query, _options, _params) do
    tags_path = KollectiveWeb.Endpoint.url() <> "/api/discovery/hashtag?tag="
    tags = preprocess_uri_query(query) |> String.split(~r/[^#\w]+/u, trim: true) |> Enum.uniq_by(&String.downcase/1)
    cleaned_tags = Enum.map(tags, fn t -> String.trim_leading(t, "#") |> String.downcase() end)

    from(h in Kollective.Hashtags.Hashtag, where: h.name in ^cleaned_tags, select: h.name)
    |> Repo.all()
    |> Enum.map(fn tag -> %{name: tag, url: tags_path <> URI.encode_www_form(tag)} end)
  end

  # ─── LOGISTICAL COMPILER HELPERS ───
  defp compile_search_options(params, user) do
    limit_param = params["limit"] || 20
    parsed_limit = if is_binary(limit_param), do: String.to_integer(limit_param), else: limit_param

    [
      following: Map.get(params, "following") == "true",
      limit: min(parsed_limit, @search_limit),
      offset: String.to_integer(params["offset"] || "0"),
      for_user: user
    ]
  end

  defp preprocess_uri_query(query) do
    if query =~ ~r/https?:\/\//, do: List.last(String.split(String.trim_trailing(query, "/"), "/")), else: query
  end

  defp with_fallback(f, fallback) do
    try do
      f.()
    rescue
      error ->
        Logger.error("#{__MODULE__} background parallel search exception: #{inspect(error)}")
        fallback
    end
  end

  # GET /api/v1/search/location (Targeted geographical coordinate locator lookup)
  @spec location(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def location(conn, %{"q" => query} = params) do
    result = with_fallback(fn ->
      Geospatial.Service.service().search(String.trim(query), Map.to_list(params))
    end, [])

    json(conn, %{locations: result})
  end

end

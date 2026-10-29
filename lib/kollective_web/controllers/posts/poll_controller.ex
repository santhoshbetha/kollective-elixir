# lib/kollective_web/controllers/posts/poll_controller.ex
defmodule KollectiveWeb.PollController do
  use KollectiveWeb, :controller
  alias Kollective.Polls.Polls
  alias Kollective.Posts.Posts
  alias KollectiveWeb.PollJSON
  alias KollectiveWeb.PostJSON
  alias KollectiveWeb.Plugs.AuthorizeOrgSocialAction

  plug AuthorizeOrgSocialAction when action in [:vote]

  # GET /api/v1/polls/stream
  def stream(conn, params) do
    current_user = conn.assigns[:current_user]

    # Ensure feed engine filters specifically for posts attached to a poll
    params = Map.put(params, "has_poll", "true")

    %{entries: entries, next_cursor: next_cursor} =
      Posts.list_posts_for_feed(current_user, params)

    serialized_posts = PostJSON.index(%{entries: entries})
    polls_list = Enum.map(serialized_posts, &format_poll_card_item/1)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: serialized_posts,
      polls: polls_list,
      next_cursor: next_cursor
    })
  end

  # GET /api/v1/polls/:id
  def show(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Polls.get_poll_results(id, user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Poll not found"})

      poll ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", poll: PollJSON.data(poll)})
    end
  end

  # POST /api/v1/polls
  def create(conn, params) do
    user = conn.assigns.current_user
    poll_data = Map.get(params, "poll", params)

    question =
      Map.get(poll_data, "question") || Map.get(poll_data, "content") ||
        Map.get(poll_data, "text") || ""

    options = Map.get(poll_data, "options") || []
    duration = Map.get(poll_data, "duration") || Map.get(poll_data, "expires_in") || "7 Days"
    audience = Map.get(poll_data, "audience") || Map.get(poll_data, "target_scope") || "world"

    expires_in = parse_duration(duration)

    post_params = %{
      "content" => question,
      "text" => question,
      "target_scope" => parse_audience(audience),
      "visibility" => "public",
      "poll" => %{
        "options" => options,
        "expires_in" => expires_in
      }
    }

    case Posts.create_post(user, post_params) do
      {:ok, post} ->
        post = Kollective.Repo.preload(post, [:author, poll: :options])

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          data: PostJSON.show(post),
          post: PostJSON.show(post),
          poll: (post.poll && PollJSON.data(post.poll)) || nil
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create poll", details: format_changeset_errors(changeset)})
    end
  end

  # POST /api/v1/polls/:poll_id/votes
  def vote(conn, params) do
    voter_id =
      if conn.assigns[:account_type] == :organization and conn.assigns[:current_organization] do
        conn.assigns[:current_organization].id
      else
        conn.assigns.current_user.id
      end

    poll_id = params["poll_id"] || params["id"]

    choices =
      cond do
        is_list(params["choices"]) -> params["choices"]
        not is_nil(params["choices"]) -> [params["choices"]]
        not is_nil(params["choice"]) -> [params["choice"]]
        not is_nil(params["option_id"]) -> [params["option_id"]]
        not is_nil(params["option_ids"]) && is_list(params["option_ids"]) -> params["option_ids"]
        true -> []
      end

    case Polls.cast_votes(voter_id, poll_id, choices) do
      {:ok, _result} ->
        poll = Polls.get_poll_results(poll_id, voter_id)

        conn
        |> put_status(:ok)
        |> json(%{status: "success", poll: PollJSON.data(poll)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Poll not found"})

      {:error, :already_voted} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Already voted"})

      {:error, :poll_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Poll has expired"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})
    end
  end

  defp parse_duration(duration) when is_integer(duration), do: duration
  defp parse_duration("24 Hours"), do: 86_400
  defp parse_duration("1 Day"), do: 86_400
  defp parse_duration("3 Days"), do: 3 * 86_400
  defp parse_duration("7 Days"), do: 7 * 86_400
  defp parse_duration("2 Weeks"), do: 14 * 86_400
  defp parse_duration("14 Days"), do: 14 * 86_400
  defp parse_duration(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, ""} -> num
      {num, " Days"} -> num * 86_400
      {num, " Day"} -> num * 86_400
      {num, "d"} -> num * 86_400
      {num, "h"} -> num * 3600
      _ -> 7 * 86_400
    end
  end
  defp parse_duration(_), do: 7 * 86_400

  defp parse_audience(nil), do: "world"
  defp parse_audience(aud) do
    case String.downcase(to_string(aud)) do
      "local" -> "local"
      "my_location" -> "local"
      "state" -> "state"
      "country" -> "country"
      "national" -> "country"
      _ -> "world"
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
  defp format_changeset_errors(other), do: to_string(other)

  defp format_poll_card_item(post_item) do
    poll_data = post_item[:poll] || post_item["poll"] || %{}
    author_data = post_item[:author] || post_item["author"] || %{}

    author_name =
      cond do
        is_binary(author_data) ->
          author_data

        is_map(author_data) ->
          author_data[:username] || author_data["username"] || author_data[:name] ||
            author_data["name"] || "user"

        true ->
          "user"
      end

    author_avatar =
      if is_map(author_data) do
        author_data[:avatar_url] || author_data["avatar_url"] || author_data[:avatar] ||
          author_data["avatar"]
      else
        nil
      end

    poll_options = Map.get(poll_data, :options) || Map.get(poll_data, "options") || []
    votes_count = Map.get(poll_data, :votes_count) || Map.get(poll_data, "votes_count") || 0

    formatted_options =
      Enum.map(poll_options, fn opt ->
        title_val =
          Map.get(opt, :title) || Map.get(opt, "title") || Map.get(opt, :text) ||
            Map.get(opt, "text")

        votes_val =
          Map.get(opt, :votes_count) || Map.get(opt, "votes_count") || Map.get(opt, :votes) ||
            Map.get(opt, "votes") || 0

        percent_val =
          if votes_count > 0 do
            Float.round(votes_val / votes_count * 100, 1)
          else
            0.0
          end

        %{
          id: to_string(Map.get(opt, :id) || Map.get(opt, "id")),
          title: title_val,
          text: title_val,
          votes: votes_val,
          votesCount: votes_val,
          votes_count: votes_val,
          percent: Map.get(opt, :percent) || Map.get(opt, "percent") || percent_val
        }
      end)

    expired = Map.get(poll_data, :expired) || Map.get(poll_data, "expired") || false
    voted = Map.get(poll_data, :voted) || Map.get(poll_data, "voted") || false

    own_votes = Map.get(poll_data, :own_votes) || Map.get(poll_data, "own_votes") || []
    first_vote = List.first(own_votes)

    voted_index =
      Enum.find_index(poll_options, fn opt ->
        opt_id = Map.get(opt, :id) || Map.get(opt, "id")
        to_string(opt_id) == to_string(first_vote)
      end) || first_vote

    Map.merge(post_item, %{
      question:
        post_item[:text] || post_item["text"] || post_item[:content] || post_item["content"],
      author: author_name,
      authorAvatar: author_avatar,
      active: not expired,
      expired: expired,
      totalVotes: votes_count,
      votes_count: votes_count,
      voted: voted,
      votedIndex: voted_index,
      own_votes: own_votes,
      scope:
        post_item[:scope] || post_item["scope"] || post_item[:target_scope] ||
          post_item["target_scope"] || "world",
      options: formatted_options,
      poll: poll_data
    })
  end
end

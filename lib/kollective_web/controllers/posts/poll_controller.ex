# lib/kollective_web/controllers/posts/poll_controller.ex
defmodule KollectiveWeb.PollController do
  use KollectiveWeb, :controller
  alias Kollective.Polls.Polls
  alias Kollective.Posts.Posts
  alias KollectiveWeb.PollJSON
  alias KollectiveWeb.PostJSON

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

  # POST /api/v1/polls/:id/votes
  def vote(conn, %{"poll_id" => poll_id, "choices" => choices}) do
    user_id = conn.assigns.current_user.id

    case Polls.cast_votes(user_id, poll_id, choices) do
      {:ok, _result} ->
        poll = Polls.get_poll_results(poll_id, user_id)

        conn
        |> put_status(:ok)
        |> json(%{status: "success", poll: PollJSON.data(poll)})

      {:error, :already_voted} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Already voted"})

      {:error, :poll_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Poll has expired"})
    end
  end

  defp format_poll_card_item(post_item) do
    poll_data = post_item[:poll] || post_item["poll"] || %{}
    author_data = post_item[:author] || post_item["author"] || %{}

    author_name =
      cond do
        is_binary(author_data) ->
          author_data

        is_map(author_data) ->
          author_data[:username] || author_data["username"] || author_data[:name] || author_data["name"] || "user"

        true ->
          "user"
      end

    author_avatar =
      if is_map(author_data) do
        author_data[:avatar_url] || author_data["avatar_url"] || author_data[:avatar] || author_data["avatar"]
      else
        nil
      end

    poll_options = Map.get(poll_data, :options) || Map.get(poll_data, "options") || []

    formatted_options =
      Enum.map(poll_options, fn opt ->
        title_val = Map.get(opt, :title) || Map.get(opt, "title") || Map.get(opt, :text) || Map.get(opt, "text")
        votes_val = Map.get(opt, :votes_count) || Map.get(opt, "votes_count") || Map.get(opt, :votes) || Map.get(opt, "votes") || 0

        %{
          id: to_string(Map.get(opt, :id) || Map.get(opt, "id")),
          title: title_val,
          text: title_val,
          votes: votes_val,
          votesCount: votes_val,
          votes_count: votes_val,
          percent: Map.get(opt, :percent) || Map.get(opt, "percent") || 0.0
        }
      end)

    expired = Map.get(poll_data, :expired) || Map.get(poll_data, "expired") || false
    votes_count = Map.get(poll_data, :votes_count) || Map.get(poll_data, "votes_count") || 0
    voted = Map.get(poll_data, :voted) || Map.get(poll_data, "voted") || false

    own_votes = Map.get(poll_data, :own_votes) || Map.get(poll_data, "own_votes") || []
    voted_index = List.first(own_votes)

    Map.merge(post_item, %{
      question: post_item[:text] || post_item["text"] || post_item[:content] || post_item["content"],
      author: author_name,
      authorAvatar: author_avatar,
      active: not expired,
      expired: expired,
      totalVotes: votes_count,
      votes_count: votes_count,
      voted: voted,
      votedIndex: voted_index,
      own_votes: own_votes,
      scope: post_item[:scope] || post_item["scope"] || post_item[:target_scope] || post_item["target_scope"] || "world",
      options: formatted_options,
      poll: poll_data
    })
  end
end

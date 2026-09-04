# lib/kollective_web/controllers/poll_controller.ex
defmodule KollectiveWeb.PollController do
  use KollectiveWeb, :controller
  alias Kollective.Polls.Polls

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
        |> json(%{status: "success", poll: serialize_poll(poll)})
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
        |> json(%{status: "success", poll: serialize_poll(poll)})

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

  defp serialize_poll(poll) do
    %{
      id: to_string(poll.id),
      expires_at: poll.expires_at,
      expired: poll.expired
    }
  end
end

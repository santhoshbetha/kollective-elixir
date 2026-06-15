# lib/kollective_web/controllers/poll_controller.ex
defmodule KollectiveWeb.PollController do
  use KollectiveWeb, :controller
  alias Kollective.Polls.Polls

  # GET /api/v1/polls/:id
  def show(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Polls.get_poll_results(id, user_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Poll not found"})
      poll ->
        render(conn, :show, poll: poll)
    end
  end

  # POST /api/v1/polls/:id/votes
  def vote(conn, %{"poll_id" => poll_id, "choices" => choices}) do
    user_id = conn.assigns.current_user.id

    # 'choices' is an array of option IDs [12, 14]
    case Polls.cast_votes(user_id, poll_id, choices) do
      {:ok, _result} ->
        # Return the fresh results so React updates immediately
        poll = Polls.get_poll_results(poll_id, user_id)
        render(conn, :show, poll: poll)

      {:error, :already_voted} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Already voted"})

      {:error, :poll_expired} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Poll has expired"})
    end
  end
end

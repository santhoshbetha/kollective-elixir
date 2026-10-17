defmodule KollectiveWeb.JuryVoteController do
  use KollectiveWeb, :controller

  alias Kollective.Voting.Voting

  action_fallback KollectiveWeb.FallbackController

  @doc """
  Handles POST /api/v1/voting/applications/:application_id/votes
  Expected JSON Body: { "vote": "approve" } OR { "vote": "reject" }
  """
  def cast_vote(conn, %{"application_id" => app_id_str, "vote" => vote_value}) do
    # 1. Retrieve the authenticated user's ID from your auth pipeline assigns
    current_user_id = conn.assigns.current_user.id
    application_id = app_id_str

    # 2. Strict whitelist check to reject invalid vote strings early
    if vote_value in ["approve", "reject"] do
      # 3. Delegate authentication verification and execution to the context layer
      case Voting.record_jury_vote(application_id, current_user_id, vote_value) do
        {:ok, _jury_record} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message: "Your blind ballot has been cast and recorded securely."
          })

        {:error, :not_authorized} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You are not an assigned juror for this application pool."})

        {:error, :already_voted} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "You have already cast a ballot for this review session."})

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to finalize your ballot data structure."})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invalid ballot value. Value must be exactly 'approve' or 'reject'."})
    end
  end
end

defmodule KollectiveWeb.JournalistController do
  use KollectiveWeb, :controller

  alias Kollective.Voting.JournalistVetting

  @doc """
  POST /api/v1/voting/journalist-verify
  Body parameters: %{"portfolio_url" => "https://muckrack.com"}
  """
  def verify_portfolio(conn, %{"portfolio_url" => portfolio_url}) do
    current_user_id = conn.assigns.current_user.id

    # Enforce basic HTTP structure string checks early
    if String.starts_with?(portfolio_url, ["http://", "https://"]) do
      case JournalistVetting.verify_via_media_registry(current_user_id, portfolio_url) do
        {:ok, updated_user} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message: "Press credentials authenticated successfully via digital media repository.",
            badge_type: updated_user.badge_type
          })

        {:error, :invalid_press_credentials} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Provided URL does not map to an active portfolio account."})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        error: "Malformed media URL structure. Must include standard http/https prefixes."
      })
    end
  end
end

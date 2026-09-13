# lib/kollective_web/controllers/auth_controller.ex
defmodule KollectiveWeb.AuthController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts

  # 🛡️ Human Gate Firewall: Prevents botnets from cycling usernames to harvest profile data
  plug KollectiveWeb.Plugs.RateLimiter, [name: :username_check] when action == :check_username

  @doc """
  GET /api/v1/auth/check-username?username=alice
  Provides instantaneous existential availability feedback for registration forms .
  """
  def check_username(conn, %{"username" => username}) do
    # Clean the input: Strip white spaces, remove leading '@', and enforce alphanumeric structures
    cleaned_username =
      username
      |> to_string()
      |> String.trim()
      |> String.trim_leading("@")

    # Guard Clause: Enforce minimal character thresholds and reject illegal URL characters
    cond do
      String.length(cleaned_username) < 2 ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", code: "too_short", available: false})

      String.length(cleaned_username) > 30 ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", code: "too_long", available: false})

      not String.match?(cleaned_username, ~r/^[a-zA-Z0-9_]+$/) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", code: "invalid_characters", available: false})

      true ->
        # Execute the high-speed index scan pass
        taken? = Accounts.username_taken?(cleaned_username)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          available: not taken?,
          username: cleaned_username
        })
    end
  end

  # Fallback catch-all guard matching empty input actions
  def check_username(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "Missing username parameter."})
end

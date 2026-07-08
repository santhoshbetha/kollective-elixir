defmodule KollectiveWeb.ConfirmationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User

  # 1. RESEND CONFIRMATION LINK
  def resend(conn, %{"user" => %{"email" => email}}) do
    case Accounts.get_user_by_email(email) do
      # Fixed the pattern match: get_user_by_email returns a flat %User{} struct
      %User{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          message: "Failed to resend confirmation email",
          errors: ["User already confirmed"]
        })

      user when not is_nil(user) ->
        # Point this link directly to your separate FRONTEND React/Mobile URL handler!
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &"https://kollective.social/confirm?token=#{&1}"
          )

        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Confirmation email sent successfully"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "User not found"})
    end
  end

  # 2. VERIFY EMAIL TOKEN (Pure Asynchronous JSON endpoint called by React)
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Email confirmed successfully", user: user})

      :error ->
        # If token is invalid or expired, return a 422 JSON payload directly
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "The confirmation link is invalid or has expired."})
    end
  end
end

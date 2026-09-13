defmodule KollectiveWeb.ConfirmationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.User

  # 1. RESEND CONFIRMATION LINK
  def resend(conn, %{"user" => %{"email" => email}}) do
    case Accounts.get_user_by_email(email) do
      %User{} = user when not is_nil(user.confirmed_at) or user.is_confirmed ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          message: "Failed to resend confirmation email",
          errors: ["User already confirmed"]
        })

      %User{} = user ->
        # Point this link directly to your separate FRONTEND React/Mobile URL handler!
        case Accounts.deliver_user_confirmation_instructions(
               user,
               &"https://kollective.social/confirm?token=#{&1}"
             ) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{status: "success", message: "Confirmation email sent successfully"})

          {:error, :already_confirmed} ->
            conn
            |> put_status(:conflict)
            |> json(%{
              status: "error",
              message: "Failed to resend confirmation email",
              errors: ["User already confirmed"]
            })
        end

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
        |> json(%{
          status: "success",
          message: "Email confirmed successfully",
          user: %{
            id: to_string(user.id),
            email: user.email,
            username: user.username,
            is_confirmed: true
          }
        })

      :error ->
        # If token is invalid or expired, return a 422 JSON payload directly
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "The confirmation link is invalid or has expired."})
    end
  end
end

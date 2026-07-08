defmodule KollectiveWeb.RegistrationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  def create(conn, %{"user" => user_params}) do
    case register_user(user_params) do
      {:ok, user} ->
        # 1. Update the mailer template link to your FRONTEND app domain, not Phoenix HTML
        _ =
          Accounts.deliver_login_instructions(
            user,
            &"https://kollective.social#{&1}"
          )

        # 2. Automatically generate an API session token so they are logged in right away
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:created)
        |> json(%{
          message: "Registration successful. Please check your email to confirm your account.",
          data: %{
            token: token,
            user: %{
              id: user.id,
              email: user.email
            }
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        # 3. Formats database validation validation errors into readable JSON key/value pairs
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        # 422
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Registration failed"})
    end
  end

  defp register_user(params) do
    params =
      params
      |> Map.take(["email", "password", "first_name", "last_name", "phone_number"])
      |> Map.put("nickname", params["username"])
      |> Map.put(
        "password_confirmation",
        Map.get(params, "password_confirmation", params["password"])
      )
      |> Map.put("birthday", params["birthday"])
      |> Map.put("gender", params["gender"])
      |> Map.put("state_code", params["state_code"])

    create_user(params)
  end

  defp create_user(params) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, other} ->
        {:error, other}
    end
  end
end

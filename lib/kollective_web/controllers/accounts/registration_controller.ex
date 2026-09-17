defmodule KollectiveWeb.RegistrationController do
  use KollectiveWeb, :controller

  alias Kollective.Accounts.Accounts

  def create(conn, %{"user" => user_params}) do
    handle_registration(conn, user_params)
  end

  def create(conn, user_params) when is_map(user_params) do
    handle_registration(conn, user_params)
  end

  defp handle_registration(conn, user_params) do
    case register_user(user_params) do
      {:ok, user} ->
        _ =
          Accounts.deliver_login_instructions(
            user,
            &"https://kollective.social#{&1}"
          )

        token = Accounts.generate_user_session_token(user)

        user_data = %{
          id: user.id,
          email: user.email,
          type: to_string(user.type),
          display_name: user.display_name
        }

        user_data =
          if user.representative_name do
            Map.put(user_data, :representative_name, user.representative_name)
          else
            user_data
          end

        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          user: user_data,
          message: "Registration successful. Please check your email to confirm your account.",
          data: %{
            token: token,
            user: user_data
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Registration failed"})
    end
  end

  defp register_user(params) do
    params = stringify_keys(params)

    allowed_keys = [
      "email",
      "password",
      "display_name",
      "displayname",
      "org_name",
      "org name",
      "Org name",
      "organization_name",
      "representative_name",
      "representative name",
      "Representative name",
      "username",
      "birthday",
      "date_of_birth",
      "country",
      "type"
    ]

    type =
      case params["type"] do
        type when type in ["organization", :organization] -> "organization"
        _ -> "citizen"
      end

    display_name =
      if type == "organization" do
        params["Org name"] || params["org name"] || params["org_name"] ||
          params["organization_name"] || params["display_name"] || params["displayname"]
      else
        params["display_name"] || params["displayname"]
      end

    representative_name =
      params["representative_name"] || params["representative name"] ||
        params["Representative name"]

    # Birthday / date of birth is not required for organization accounts
    date_of_birth =
      if type == "organization" do
        nil
      else
        params["date_of_birth"] || params["birthday"]
      end

    drop_keys = [
      "displayname",
      "birthday",
      "org_name",
      "org name",
      "Org name",
      "organization_name",
      "representative name",
      "Representative name"
    ]

    drop_keys =
      if type == "organization" do
        ["date_of_birth" | drop_keys]
      else
        drop_keys
      end

    params
    |> Map.take(allowed_keys)
    |> maybe_put("display_name", display_name)
    |> maybe_put("representative_name", representative_name)
    |> maybe_put("date_of_birth", date_of_birth)
    |> Map.put("type", type)
    |> Map.drop(drop_keys)
    |> create_user()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_keys(other), do: other

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

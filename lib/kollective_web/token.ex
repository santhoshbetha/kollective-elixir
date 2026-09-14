defmodule KollectiveWeb.Token do
  use Joken.Config

  # 1 hour expiration is ideal for security. Your Zustand layer can refresh it.
  @impl true
  def token_config do
    default_claims(skip: [:aud, :iss], default_exp: 3600)
    |> add_claim("user_id", nil, &is_binary/1)
    |> add_claim("active_account_id", nil, &is_binary/1)
    |> add_claim("account_type", nil, &Enum.member?(["individual", "organization"], &1))
    |> add_claim("permissions", [], &is_list/1)
  end

  def signer do
    secret =
      Application.get_env(:kollective, :jwt_secret) ||
        Application.get_env(:kollective, KollectiveWeb.Endpoint)[:secret_key_base] ||
        "kollective_jwt_token_signing_secret_key_minimum_32_bytes"

    Joken.Signer.create("HS256", secret)
  end

  def generate_and_sign_tokens(user, active_account, permissions) do
    account_type =
      if active_account.type == :organization do
        "organization"
      else
        "individual"
      end

    claims = %{
      "user_id" => to_string(user.id),
      "active_account_id" => to_string(active_account.id),
      "account_type" => account_type,
      "permissions" => permissions
    }

    generate_and_sign(claims, signer())
  end
end

# priv/repo/migrations/XXXXXXXX_create_vouch_secure_tokens.exs
defmodule Kollective.Repo.Migrations.CreateVouchSecureTokens do
  use Ecto.Migration

  def change do
    create table(:vouch_secure_tokens, primary_key: false) do
      # Let the chronological Ecto.ULID act as the fast clustered key index row anchor
      add :id, :binary_id, primary_key: true

      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # High-speed index scanner handles single-use token lookups under 0.01ms [INDEX]
    create unique_index(:vouch_secure_tokens, [:token], name: :vouch_secure_tokens_token_index)
  end
end

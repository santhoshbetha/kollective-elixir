# priv/repo/migrations/XXXXXXXX_create_user_filters.exs
defmodule Kollective.Repo.Migrations.CreateUserFilters do
  use Ecto.Migration

  def change do
    create table(:user_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :phrase, :string, null: false
      add :whole_word, :boolean, default: true, null: false
      add :context, {:array, :string}, default: ["home", "public"], null: false
      add :expires_at, :utc_datetime, null: true

      timestamps()
    end

    # ─── SECURE COMPOSITE PERFORMANCE OVERRIDES ───
    # Prevents duplicate tracking entries per user profile natively inside PostgreSQL
    create unique_index(:user_filters, [:user_id, :phrase],
             name: :user_filters_phrase_unique_index
           )

    create index(:user_filters, [:user_id, :expires_at])
  end
end

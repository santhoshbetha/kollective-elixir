# priv/repo/migrations/XXXXXXXX_create_post_reactions.exs
defmodule Kollective.Repo.Migrations.CreatePostReactions do
  use Ecto.Migration

  def change do
    create table(:post_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      # Store the literal emoji character string (e.g., "🔥", "👍")
      add :emoji, :string, null: false

      timestamps()
    end

    # Enforce that a unique user can only react with a specific emoji once per post
    create unique_index(:post_reactions, [:user_id, :post_id, :emoji],
             name: :post_reactions_composite_unique_index
           )

    create index(:post_reactions, [:post_id])
    create index(:post_reactions, [:user_id])
  end
end

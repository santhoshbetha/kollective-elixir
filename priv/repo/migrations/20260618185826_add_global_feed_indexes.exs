# To make global filtering instantaneous, you must add a composite index that
# groups visibility, status, category, and id. This lets PostgreSQL scan directly down
# the pre-sorted columns under 1ms.
defmodule Kollective.Repo.Migrations.AddGlobalFeedIndexes do
  use Ecto.Migration

  def change do
    # Critical index for "All Activity" and "Posts" tabs
    create index(:posts, [:visibility, :status, :category, :id])

    # Critical index for "Voices" trending tab calculations
    create index(:posts, [:visibility, :status, :category, :trending_score, :id])
  end
end

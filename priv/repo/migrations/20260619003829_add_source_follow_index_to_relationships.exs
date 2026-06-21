defmodule Kollective.Repo.Migrations.AddSourceFollowIndexToRelationships do
  use Ecto.Migration

  def change do
    # Creates a high-speed targeted search path for follow lists
    create index(:user_relationships, [:source_id, :type, :target_id])
  end
end

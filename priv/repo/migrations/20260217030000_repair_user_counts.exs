# Repair Migration (The "Safety Net")
# If counts ever get out of sync, you can run a one-time "repair" migration. This uses a subquery to
# count the actual rows in your user_relationships table and updates the users table.

defmodule Kollective.Repo.Migrations.RepairUserCounts do
  use Ecto.Migration

  def up do
    # Update following_count for all users
    execute """
    UPDATE users u
    SET following_count = (
      SELECT count(*) FROM user_relationships r
      WHERE r.source_id = u.id AND r.type = 'follow'
    )
    """

    # Update follower_count for all users
    execute """
    UPDATE users u
    SET follower_count = (
      SELECT count(*) FROM user_relationships r
      WHERE r.target_id = u.id AND r.type = 'follow'
    )
    """
  end

  def down, do: :ok
end

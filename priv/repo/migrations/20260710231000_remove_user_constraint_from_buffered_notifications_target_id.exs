defmodule Kollective.Repo.Migrations.RemoveUserConstraintFromBufferedNotificationsTargetId do
  use Ecto.Migration

  def change do
    drop constraint(:buffered_notifications, "buffered_notifications_target_id_fkey")
  end
end

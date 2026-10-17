defmodule Kollective.Repo.Migrations.AddDeliveryIndexesToParticipants do
  use Ecto.Migration

  def change do
    alter table(:conversation_participants) do
      # 🚀 PERFORMANCE GAP MATRIX: Optimize real-time unread/delivered badge counts lookups
      add_if_not_exists :last_delivered_at, :utc_datetime
    end

    # Composite index optimizes query speeds for checking which members haven't received a message yet
    create_if_not_exists index(:conversation_participants, [
                           :conversation_id,
                           :user_id,
                           :last_delivered_at
                         ])
  end
end

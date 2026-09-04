defmodule Kollective.Repo.Migrations.AddLastDeliveredAtToConversationParticipants do
  use Ecto.Migration

  def change do
    alter table(:conversation_participants) do
      add :last_delivered_at, :utc_datetime
    end
  end
end

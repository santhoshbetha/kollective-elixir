defmodule Kollective.Repo.Migrations.AddIsProcessedToPostAttachments do
  use Ecto.Migration

  def change do
    alter table(:post_attachments) do
      add :is_processed, :boolean, default: false, null: false
    end
  end
end


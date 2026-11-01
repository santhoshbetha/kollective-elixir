defmodule Kollective.Repo.Migrations.AddFocalPointToMediaAttachments do
  use Ecto.Migration

  def change do
    alter table(:post_attachments) do
      add :focal_x, :float, default: 0.0
      add :focal_y, :float, default: 0.0
    end

    alter table(:media_attachments) do
      add :focal_x, :float, default: 0.0
      add :focal_y, :float, default: 0.0
    end
  end
end


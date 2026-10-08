defmodule Kollective.Repo.Migrations.CreateMediaAttachments do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:media_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file, :string
      add :type, :string
      add :url, :string
      add :description, :text
      add :blurhash, :string
      add :static_url, :string

      add :author_id, references(:users, on_delete: :delete_all, type: :binary_id)
      add :post_id, references(:posts, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:media_attachments, [:author_id])
    create_if_not_exists index(:media_attachments, [:post_id])
  end
end

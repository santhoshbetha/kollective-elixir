defmodule Kollective.Repo.Migrations.CreatePostAttachments do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:post_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :media, :string
      add :alt_text, :string
      add :content_type, :string
      add :is_processed, :boolean, default: false, null: false

      add :post_id,
          references(:posts, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create_if_not_exists index(:post_attachments, [:post_id])
  end
end

defmodule Kollective.Repo.Migrations.RebuildPostAttachments do
  use Ecto.Migration

  def change do
    # Wipes out the old table if it exists to cleanly purge old Waffle structure tracking columns
    drop_if_exists table(:post_attachments)

    create table(:post_attachments, primary_key: false) do
      # ─── PRIMARY KEY ───
      add :id, :binary_id, primary_key: true

      # ─── CORE CLOUD FILE ASSETS ───
      # Stores the final direct public CDN/R2 string link
      add :url, :string, null: false
      # e.g., "image/jpeg" or "video/mp4"
      add :media_type, :string, null: false
      # Holds your alt text / accessibility captions
      add :description, :text
      add :blurhash, :string, default: "", null: false

      # ─── RELATIONSHIPS ───
      # References the user who uploaded it for access control checks
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # References the post node it belongs to (nullable because it's orphaned right after creation)
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    # ─── PERFORMANCE INDICES ───
    # Speeds up authorization owner validations inside your PUT/DELETE media controllers
    create index(:post_attachments, [:user_id])

    # Optimizes streaming all attached media assets belonging to a specific post node timeline
    create index(:post_attachments, [:post_id])
  end
end

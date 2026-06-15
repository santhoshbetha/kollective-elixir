# Delete all replies when a parent post is removed, the most efficient and reliable way to handle this is at the
# Database level.

# By using Foreign Key constraints with on_delete: :delete_all, PostgreSQL will automatically "cascade"
# the deletion. If you delete the "Grandfather" (Root), every "Father" and "Child" connected to it
# disappears instantly.

defmodule Kollective.Repo.Migrations.AddCascadingDeletesToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # When a root_post is deleted, delete everything sharing that root
      modify :root_post_id, references(:posts, on_delete: :delete_all),
        from: references(:posts, on_delete: :nothing)

      # When a direct reply target is deleted, delete the reply too
      modify :in_reply_to_id, references(:posts, on_delete: :delete_all),
        from: references(:posts, on_delete: :nothing)
    end
  end
end

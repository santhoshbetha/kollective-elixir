# change the foreign key behavior to :nilify_all. This tells PostgreSQL: "If the post I'm replying to
# is deleted, just set my in_reply_to_id to NULL but keep me alive".

#Orpahn Effect:  In the UI, the reply will look like a standalone post or a "top-level" post because
#its in_reply_to_id now points to a record that doesn't exist (or is set to nil).

defmodule Kollective.Repo.Migrations.UpdateDeleteBahavior do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # When a root_post or reply target is deleted, keep the replies
      modify :root_post_id, references(:posts, on_delete: :nilify_all),
        from: references(:posts, on_delete: :delete_all)

      modify :in_reply_to_id, references(:posts, on_delete: :nilify_all),
        from: references(:posts, on_delete: :delete_all)
    end
  end
end

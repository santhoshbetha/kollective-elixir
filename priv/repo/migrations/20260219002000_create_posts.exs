defmodule Kollective.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    # Specify the primary_key: false option if you generate ULIDs manually/via schema macros
    create_if_not_exists table(:posts, primary_key: false) do
      # 👈 Configured for ULIDs/UUIDs storage
      add :id, :binary_id, primary_key: true
      add :body, :text

      # Association to the users table
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # self-referencing relationship fields:
      add :root_post_id, references(:posts, type: :binary_id, on_delete: :nothing)
      add :in_reply_to_id, references(:posts, type: :binary_id, on_delete: :nothing)

      # ➕ feed control fields required by your global index:
      # e.g., public, private
      add :visibility, :string, default: "public", null: false
      # e.g., draft, published, deleted
      add :status, :string, default: "published", null: false
      add :category, :string, default: "post", null: false

      # Trending score calculation column:
      # 👈 Track popularity metrics
      add :trending_score, :float, default: 0.0, null: false

      timestamps()
    end

    create_if_not_exists index(:posts, [:user_id])
    create_if_not_exists index(:posts, [:root_post_id])
    create_if_not_exists index(:posts, [:in_reply_to_id])
  end
end

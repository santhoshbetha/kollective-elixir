defmodule Kollective.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    # Full posts table aligned with Kollective.Posts.Post persisted schema fields.
    create_if_not_exists table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Ownership
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Threading/self-references
      add :root_post_id, references(:posts, type: :binary_id, on_delete: :nothing)
      add :in_reply_to_id, references(:posts, type: :binary_id, on_delete: :nothing)
      add :quote_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      add :reblog_of_id, references(:posts, type: :binary_id, on_delete: :nilify_all)

      # Moderation references
      add :rejected_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Content fields
      add :content, :text
      add :text, :text
      add :sensitive, :boolean, default: false, null: false
      add :spoiler_text, :text
      add :summary, :text
      add :language, :string, default: "english", null: false
      add :content_type, :string, default: "text/html", null: false
      add :emoji_reactions, {:array, :map}, default: [], null: false
      add :application_name, :string
      add :mentions, {:array, :map}, default: [], null: false
      add :event_data, :map
      add :quote_url, :string
      add :in_reply_to_username, :string
      add :context, :string
      add :direct_conversation_id, :integer

      # Lifecycle and workflow
      add :processing_status, :string, default: "pending", null: false
      add :published_at, :utc_datetime
      add :edited_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :pinned_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :rejection_reason, :text
      add :rejected_at, :utc_datetime
      add :appeal_reason, :text
      add :appealed_at, :utc_datetime

      # Feed control
      add :visibility, :string, default: "public", null: false
      add :status, :string, default: "published", null: false
      add :category, :string, default: "post", null: false
      add :local, :boolean, default: true, null: false
      add :target_scope, :string, default: "local", null: false
      add :trending_score, :float, default: 0.0, null: false
      add :urgency_level, :integer, default: 0, null: false

      # Geo targeting
      add :origin_city_id, :integer
      add :origin_state, :string
      add :origin_country, :string, default: "US", null: false
      add :origin_district_l1, :string
      add :origin_district_l2, :string
      add :origin_district_l3, :string

      # OpenGraph and metadata
      add :link_url, :text
      add :link_title, :text
      add :link_description, :text
      add :link_preview_image, :text
      add :coordination_data, :map, default: %{}, null: false
      add :data, :map, default: %{}, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create_if_not_exists index(:posts, [:user_id])
    create_if_not_exists index(:posts, [:root_post_id])
    create_if_not_exists index(:posts, [:in_reply_to_id])
    create_if_not_exists index(:posts, [:quote_id])
    create_if_not_exists index(:posts, [:reblog_of_id])
    create_if_not_exists index(:posts, [:rejected_by_id])
    create_if_not_exists index(:posts, [:status])
    create_if_not_exists index(:posts, [:category])
    create_if_not_exists index(:posts, [:target_scope])
    create_if_not_exists index(:posts, [:visibility])
  end
end

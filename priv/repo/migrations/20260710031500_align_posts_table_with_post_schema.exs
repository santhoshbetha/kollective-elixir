defmodule Kollective.Repo.Migrations.AlignPostsTableWithPostSchema do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add_if_not_exists :content, :text
      add_if_not_exists :text, :text
      add_if_not_exists :sensitive, :boolean, default: false, null: false
      add_if_not_exists :spoiler_text, :text
      add_if_not_exists :summary, :text
      add_if_not_exists :language, :string, default: "english", null: false
      add_if_not_exists :content_type, :string, default: "text/html", null: false
      add_if_not_exists :emoji_reactions, {:array, :map}, default: [], null: false
      add_if_not_exists :application_name, :string
      add_if_not_exists :mentions, {:array, :map}, default: [], null: false
      add_if_not_exists :event_data, :map
      add_if_not_exists :in_reply_to_username, :string
      add_if_not_exists :context, :string
      add_if_not_exists :direct_conversation_id, :integer
      add_if_not_exists :quote_url, :string

      # add_if_not_exists :quote_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      # add_if_not_exists :reblog_of_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      # add_if_not_exists :rejected_by_id,
      # references(:users, type: :binary_id, on_delete: :nilify_all)

      add_if_not_exists :processing_status, :string, default: "pending", null: false
      add_if_not_exists :published_at, :utc_datetime
      add_if_not_exists :edited_at, :utc_datetime
      add_if_not_exists :expires_at, :utc_datetime
      add_if_not_exists :pinned_at, :utc_datetime
      add_if_not_exists :deleted_at, :utc_datetime
      add_if_not_exists :rejection_reason, :text
      add_if_not_exists :rejected_at, :utc_datetime
      add_if_not_exists :appeal_reason, :text
      add_if_not_exists :appealed_at, :utc_datetime

      add_if_not_exists :local, :boolean, default: true, null: false
      add_if_not_exists :target_scope, :string, default: "local", null: false
      add_if_not_exists :urgency_level, :integer, default: 0, null: false

      add_if_not_exists :origin_city_id, :integer
      add_if_not_exists :origin_state, :string
      add_if_not_exists :origin_country, :string, default: "US", null: false
      add_if_not_exists :origin_district_l1, :string
      add_if_not_exists :origin_district_l2, :string
      add_if_not_exists :origin_district_l3, :string

      add_if_not_exists :link_url, :text
      add_if_not_exists :link_title, :text
      add_if_not_exists :link_description, :text
      add_if_not_exists :link_preview_image, :text
      add_if_not_exists :coordination_data, :map, default: %{}, null: false
      add_if_not_exists :data, :map, default: %{}, null: false
      add_if_not_exists :metadata, :map, default: %{}, null: false
    end

    create_if_not_exists index(:posts, [:quote_id])
    create_if_not_exists index(:posts, [:reblog_of_id])
    create_if_not_exists index(:posts, [:rejected_by_id])
    create_if_not_exists index(:posts, [:status])
    create_if_not_exists index(:posts, [:category])
    create_if_not_exists index(:posts, [:target_scope])
    create_if_not_exists index(:posts, [:visibility])
  end
end

defmodule Kollective.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :naive_datetime

      # Text and Profile Metadata Fields
      add :identity_hash, :string
      add :type, :string, default: "standard", null: false
      add :role, :string, default: "user", null: false
      add :bio, :text
      add :raw_bio, :text
      add :avatar_url, :string
      add :cover_image_url, :string
      add :background, :string
      add :emoji, :string
      add :locale, :string, default: "en"
      add :language, :string, default: "english"
      add :country, :string
      add :experience_mode, :string
      add :default_scope, :string, default: "public"

      # Boolean System Flags
      add :is_active, :boolean, default: true, null: false
      add :is_confirmed, :boolean, default: false, null: false
      add :is_admin, :boolean, default: false, null: false
      add :is_moderator, :boolean, default: false, null: false
      add :is_invisible, :boolean, default: false, null: false
      add :is_candidate, :boolean, default: false, null: false
      add :is_verified, :boolean, default: false, null: false
      add :is_verified_candidate, :boolean, default: false, null: false
      add :is_shadow_banned, :boolean, default: false, null: false
      add :is_exempt, :boolean, default: false, null: false
      add :is_locked, :boolean, default: false, null: false
      add :is_discoverable, :boolean, default: true, null: false
      add :is_suggested, :boolean, default: false, null: false
      add :password_reset_pending, :boolean, default: false, null: false

      # Privacy and Display Preference Flags
      add :show_role, :boolean, default: true, null: false
      add :show_age, :boolean, default: false, null: false
      add :hide_favorites, :boolean, default: false, null: false
      add :hide_follows, :boolean, default: false, null: false
      add :hide_follows_count, :boolean, default: false, null: false
      add :hide_followers, :boolean, default: false, null: false
      add :hide_followers_count, :boolean, default: false, null: false
      add :email_notifications, :map, default: "{\"digest\": false}", null: false
      add :accepts_email_list, :boolean, default: false, null: false
      add :auto_play_gifs, :boolean, default: true, null: false
      add :no_rich_text, :boolean, default: false, null: false

      # Numerical Counter and Metrics Fields
      add :following_count, :integer, default: 0, null: false
      add :follower_count, :integer, default: 0, null: false
      add :note_count, :integer, default: 0, null: false
      add :false_reports_count, :integer, default: 0, null: false
      add :successful_reports_count, :integer, default: 0, null: false
      add :report_trust_score, :float, default: 100.0, null: false

      # Complex Data Map Fields
      add :settings, :map, default: "{}"
      add :muted_keywords, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:users, [:email])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end

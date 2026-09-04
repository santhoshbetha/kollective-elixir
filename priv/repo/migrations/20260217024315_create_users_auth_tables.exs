defmodule Kollective.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      # ─── PRIMARY KEY & CORE AUTH ───
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      add :username, :string, null: false
      add :display_name, :string
      add :alias_name, :string

      # ─── CORE FLAGS & CONFIG ───
      add :is_confirmed, :boolean, default: false, null: false
      add :is_active, :boolean, default: true, null: false
      add :is_discoverable, :boolean, default: true, null: false
      add :is_invisible, :boolean, default: false, null: false
      add :is_suggested, :boolean, default: false, null: false
      add :is_admin, :boolean, default: false, null: false
      add :is_moderator, :boolean, default: false, null: false
      # Ecto.Enum -> string
      add :role, :string, default: "user", null: false
      # Ecto.Enum -> string
      add :type, :string, default: "citizen", null: false
      add :experience_mode, :string, default: "social_only", null: false
      add :default_scope, :string, default: "public", null: false

      # ─── BIO & METADATA ───
      add :bio, :text, default: ""
      add :raw_bio, :text, default: ""
      add :identity_hash, :string, default: ""
      add :badge_type, :string, default: "ClassicBlue", null: false
      add :professional_credentials, :text
      add :locale, :string, default: "en", null: false
      add :language, :string, default: "en", null: false
      add :first_name, :string
      add :last_name, :string

      # ─── LOCATION & DISTRICT ASSOCIATIONS ───
      add :location, :string

      add :district_l1_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      add :district_l2_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      add :district_l3_id,
          references(:political_districts, type: :binary_id, on_delete: :nilify_all)

      add :precinct, :string
      add :city_id, references(:cities, type: :binary_id, on_delete: :nilify_all)
      add :city_name, :string
      add :state, :string
      add :country, :string, default: "US", null: false

      # ─── CANDIDACY & VERIFICATION ───
      add :is_candidate, :boolean, default: false, null: false
      add :is_verified_candidate, :boolean, default: false, null: false
      # Ecto.Enum -> string
      add :candidate_role, :string
      add :verification_id, :string
      add :verified_title, :string
      add :official_website, :string

      # ─── ASSET URLS ───
      add :avatar_url, :string, default: "/default-avatar.jpg", null: false
      add :cover_image_url, :string, default: "/default-banner-bg.jpg", null: false

      # ─── METRIC COUNTERS ───
      add :note_count, :integer, default: 0, null: false
      add :follower_count, :integer, default: 0, null: false
      add :following_count, :integer, default: 0, null: false

      # ─── MAPS & JSON PAYLOADS (EMBEDS) ───
      add :settings, :map, default: "{}", null: false
      add :email_notifications, :map, default: "{\"digest\": false}", null: false
      # Handles embeds_one
      add :notification_settings, :map, default: "{}", null: false
      add :emoji, :map, default: "{}", null: false
      add :background, :map, default: "{}", null: false

      # ─── DEMOGRAPHICS ───
      add :age, :integer
      add :birth_year, :integer
      add :show_age, :boolean, default: false, null: false

      # ─── MODERATION & TRUST SCORES ───
      add :is_shadow_banned, :boolean, default: false, null: false
      add :is_exempt, :boolean, default: false, null: false
      add :is_verified, :boolean, default: false, null: false
      add :is_locked, :boolean, default: false, null: false
      add :report_trust_score, :float, default: 1.0, null: false
      add :successful_reports_count, :integer, default: 0, null: false
      add :false_reports_count, :integer, default: 0, null: false
      add :muted_keywords, {:array, :string}, default: [], null: false
      add :suspended_at, :utc_datetime
      add :suspension_reason, :string

      # ─── PREFERENCES & PRIVACY ───
      add :show_role, :boolean, default: true, null: false
      add :hide_followers_count, :boolean, default: false, null: false
      add :hide_follows_count, :boolean, default: false, null: false
      add :hide_followers, :boolean, default: false, null: false
      add :hide_follows, :boolean, default: false, null: false
      add :hide_favorites, :boolean, default: true, null: false
      add :no_rich_text, :boolean, default: false, null: false
      add :auto_play_gifs, :boolean, default: false, null: false
      add :accepts_chat_messages, :boolean
      add :accepts_email_list, :boolean, default: false, null: false

      # ─── TIMING ARCHIVES ───
      add :last_active_at, :utc_datetime
      add :last_digest_emailed_at, :naive_datetime
      add :last_post_at, :naive_datetime
      add :last_read_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :password_reset_pending, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

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

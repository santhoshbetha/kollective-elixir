defmodule Kollective.Accounts.User do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  alias Kollective.Accounts.NotificationSetting

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # --- IDENTITY ---
    field :username, :string
    field :locale, :string, default: "en" # ISO 639-1 code #preferred language
    field :first_name, :string
    field :last_name, :string
    field :bio, :string, default: ""
    # Useful for search indexing
    field :raw_bio, :string, default: ""

    # --- AUTHENTICATION (Phx.Gen.Auth style) ---
    field :is_confirmed, :boolean, default: false
    field :is_active, :boolean, default: true

    # User Types: :regular, :scholar, :journalist
    field :type, Ecto.Enum, values: [:regular, :scholar, :journalist], default: :regular

    # For Scholars/Journalists: Specialized bio or verification notes
    field :professional_credentials, :string

    # Optional: Mark if this user is an active candidate
    field :is_candidate, :boolean, default: false

    # --- LOCATION & DISCOVERY ---
    # User-facing location string
    field :location, :string
    field :language, :string, default: "en"
    field :is_discoverable, :boolean, default: true
    field :is_suggested, :boolean, default: false
    field :last_active_at, :utc_datetime

    # --- GEOGRAPHIC LOCATION ---
    # --- POLITICAL/ELECTORAL DISTRICTS ---
    # These allow "Voice" posts to target specific representative groups

    # e.g., "CA-12" (Congressional)
    # federal_district => L1 = Federal/National (MP, Congressman)
    #field :district_l1, :string
    belongs_to :district_l1, Kollective.Locations.PoliticalDistrict # National

    # e.g., "SD-24"  (State Senate)
    # state_senate_district => L2 = State Upper House (State Senate)
    #field :district_l2, :string
    belongs_to :district_l2, Kollective.Locations.PoliticalDistrict # State Upper

    # e.g., "SD-11" (State Assembly)
    # state_district => L3 = State Lower House (State Rep, MLA)
    #field :district_l3, :string
    belongs_to :district_l3, Kollective.Locations.PoliticalDistrict # State Lower

    # Smallest local unit (optional)
    field :precinct, :string

    # Internal City ID
    #field :city_id, :integer
    belongs_to :city, Kollective.Locations.City, foreign_key: :city_id
    # Display name
    field :city_name, :string

    # e.g., "California" or "CA"
    field :state, :string
    field :country, :string, default: "US"

    # Candidate Verification
    field :is_verified_candidate, :boolean, default: false
    # Identifies the level of office the candidate is verified for
    field :candidate_role, Ecto.Enum,
      values: [:state_rep, :state_senate, :congress, :governor, :president]

    # Documentation or proof reference (e.g., link to official filing or external KYC ID)
    field :verification_id, :string

    # Profile Pages with Verification for candidates
    # e.g., "State Representative" or "City Council"
    field :verified_title, :string
    # Link to their web site or official profile for verification
    field :official_website, :string

    # --- VISUALS ---
    field :avatar, :map, default: %{}
    field :banner, :map, default: %{}

    # --- SOCIAL COUNTERS (Cached for performance) ---
    field :note_count, :integer, default: 0
    field :follower_count, :integer, default: 0
    field :following_count, :integer, default: 0

    # --- PERMISSIONS & ROLES ---
    # field :is_admin, :boolean, default: false
    field :role, Ecto.Enum, values: [:user, :moderator, :admin], default: :user
    field :is_moderator, :boolean, default: false

    # --- PREFERENCES ---
    field :settings, :map, default: %{}
    field :email_notifications, :map, default: %{"digest" => false}
    field :birthday, :date
    field :show_birthday, :boolean, default: false

    # --- ASSOCIATIONS ---
    has_many :posts, Kollective.Posts.Post
    has_many :notifications, Kollective.Notifications.Notification, on_delete: :delete_all

    # UserRelationship logic for Follows/Blocks/Mutes
    # Direct access to the relationship records
    # Base connections
    # 1. Base associations (The "Raw" Data)
    # Useful if you need to count ALL interactions (follows + blocks + mutes)
    has_many :outgoing_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id

    has_many :incoming_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :target_id

    # 2. Following Logic (Outbound "follow" type)
    has_many :following_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "follow"]

    has_many :following, through: [:following_relationships, :target]

    # 3. Follower Logic (Inbound "follow" type)
    has_many :follower_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :target_id,
      where: [type: "follow"]

    has_many :followers, through: [:follower_relationships, :source]

    # 4. Blocking Logic (Outbound "block" type)
    # Block is an outbound action
    has_many :block_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "block"]

    has_many :blocked_users, through: [:block_relationships, :target]

    # 5. Muting Logic (Outbound "mute" type)
    # Mute is an outbound action
    has_many :mute_relationships, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "mute"]

    has_many :muted_users, through: [:mute_relationships, :target]

    # Reblog Mutes (Hide boosts from this person)
    has_many :reblog_mute_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id, where: [type: "reblog_mute"]

    has_many :reblog_muted_users, through: [:reblog_mute_rels, :target]

    # Notification Mutes (Don't notify me when they interact)
    has_many :notification_mute_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id, where: [type: "notification_mute"]

    has_many :notification_muted_users, through: [:notification_mute_rels, :target]

    # Endorsements (Featured users on your profile)
    has_many :endorsement_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id, where: [type: "endorsement"]

    has_many :endorsed_users, through: [:endorsement_rels, :target]

    # Inverse Subscriptions (Requested follows / Private accounts)
    has_many :inv_sub_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id, where: [type: "inverse_subscription"]

    has_many :subscriber_users, through: [:inv_sub_rels, :target]

    # user org relationships
    many_to_many :followed_organizations, Kollective.Accounts.Organization,
      join_through: "user_organization_relationships"

    field :is_admin, :boolean, default: false

    # shadow-ban for aggressive spammers
    field :is_shadow_banned, :boolean, default: false

    # Users with true will bypass all keyword/weight checks
    field :is_exempt, :boolean, default: false

    field :is_verified, :boolean, default: false

    has_many :candidate_videos, Kollective.Videos.CandidateVideo

    # Base trust. 1.0 = 100%, 0.5 = 50% weight, etc.
    # Reputation System for reporters
    field :report_trust_score, :float, default: 1.0
    field :successful_reports_count, :integer, default: 0
    field :false_reports_count, :integer, default: 0

    field :muted_keywords, {:array, :string}, default: []

    # Hard Account Suspension
    field :suspended_at, :utc_datetime
    field :suspension_reason, :string

    field :show_role, :boolean, default: true
    field :is_locked, :boolean, default: false
    field :default_scope, :string, default: "public" #["public", "unlisted", "local", "private", "direct", "list"]

    # Privacy
    field :hide_followers_count, :boolean, default: false
    field :hide_follows_count, :boolean, default: false
    field :hide_followers, :boolean, default: false
    field :hide_follows, :boolean, default: false
    field :hide_favorites, :boolean, default: true

    # Settings & Maps
    field :emoji, :map, default: %{}
    field :background, :map, default: %{}
    field :no_rich_text, :boolean, default: false
    field :accepts_chat_messages, :boolean
    field :accepts_email_list, :boolean, default: false
    field :password_reset_pending, :boolean, default: false

    # Dates
    field :last_digest_emailed_at, :naive_datetime
    field :last_post_at, :naive_datetime

    field :last_read_at, :utc_datetime

    field :last_seen_at, :utc_datetime

    embeds_one :notification_settings, NotificationSetting, on_replace: :update

    # "Auto-play GIFs" setting in your user preferences
    field :auto_play_gifs, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :email,
      :password,
      :password_confirmation,
      :first_name,
      :last_name,
      :date_of_birth,
      :country
    ])
    |> validate_email(opts)
    |> validate_password(opts)
    |> validate_required([:first_name, :last_name, :email, :date_of_birth, :country])
    |> validate_length(:first_name, max: 100)
    |> validate_length(:last_name, max: 100)
    |> validate_inclusion(:country, ["US", "CA", "GB", "AU", "DE", "FR", "JP", "MX", "ES", "IN", "AR", "BO", "BR", "CL", "CO", "VE", "UY", "PE", "PY"]) # Example country codes
    |> put_calculated_age()
    |> put_change(:is_confirmed, false)
  end

  defp put_calculated_age(changeset) do
    case get_field(changeset, :date_of_birth) do
      %Date{} = dob ->
        age = calculate_age(dob)
        put_change(changeset, :age, age)
      _ ->
        changeset
    end
  end

  defp calculate_age(dob) do
    today = Date.utc_today()
    age = today.year - dob.year

    # Adjust if the birthday hasn't happened yet this year
    if Date.compare(today, %{dob | year: today.year}) == :lt do
      age - 1
    else
      age
    end
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Kollective.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Pbkdf2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Kollective.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end

  def district_changeset(user, attrs) do
    user
    |> cast(attrs, [:state, :district_l1, :district_l2, :district_l3])
    |> validate_required([:state])
  end

  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:auto_play_emails, :auto_play_gifs]) # Add other settings here
  end
end

#create index(:user_relationships, [:source_id, :type, :target_id], unique: true)

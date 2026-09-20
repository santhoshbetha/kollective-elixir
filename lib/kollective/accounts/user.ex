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
    field :display_name, :string
    # For pseudonyms or pen names or to hide caste/religion guessing in India
    field :alias_name, :string
    # For organizations: human contact / representative name
    field :representative_name, :string

    # ISO 639-1 code #preferred language
    field :locale, :string, default: "en"
    field :first_name, :string
    field :last_name, :string
    field :bio, :string, default: ""
    # Useful for search indexing
    field :raw_bio, :string, default: ""

    # The user's phone number or email, put through a one-way cryptographic hashing function with a secure,
    field :identity_hash, :string, default: ""
    # server-side salt (SHA-256(phone + server_secret)).

    # --- AUTHENTICATION (Phx.Gen.Auth style) ---
    field :is_confirmed, :boolean, default: false
    field :is_active, :boolean, default: true

    # User Types: :citizen, :scholar, :journalist, :activist, :organization
    # activist --> Union leaders, strike organizers, whistleblowers.
    # scholar --> Academic researchers, professors, and subject matter experts.
    # journalist --> Reporters, editors, and media professionals, Independent reporters and field correspondents.
    # organization --> Non-profits, NGOs, advocacy groups, and civic organizations.
    field :type, Ecto.Enum,
      values: [:citizen, :scholar, :journalist, :activist, :organization],
      default: :citizen

    field :badge_type, :string, default: "ClassicBlue"

    # For Scholars/Journalists: Specialized bio or verification notes
    field :professional_credentials, :string

    # Optional: Mark if this user is an active candidate
    field :is_candidate, :boolean, default: false

    # --- LOCATION & DISCOVERY ---
    # User-facing location string (stores fuzzy coordinates as WKT for safety)
    field :location, :string
    field :fuzzy_latitude, :float, virtual: true
    field :fuzzy_longitude, :float, virtual: true
    field :language, :string, default: "en"
    field :is_discoverable, :boolean, default: true
    field :is_invisible, :boolean, default: false
    field :is_suggested, :boolean, default: false
    field :last_active_at, :utc_datetime

    # --- GEOGRAPHIC LOCATION ---
    # --- POLITICAL/ELECTORAL DISTRICTS ---
    # These allow "Voice" posts to target specific representative groups

    # e.g., "CA-12" (Congressional)
    # federal_district => L1 = Federal/National (MP, Congressman)
    # field :district_l1, :string
    # National
    belongs_to :district_l1, Kollective.Locations.PoliticalDistrict

    # e.g., "SD-24"  (State Senate)
    # state_senate_district => L2 = State Upper House (State Senate)
    # field :district_l2, :string
    # State Upper
    belongs_to :district_l2, Kollective.Locations.PoliticalDistrict

    # e.g., "SD-11" (State Assembly)
    # state_district => L3 = State Lower House (State Rep, MLA)
    # field :district_l3, :string
    # State Lower
    belongs_to :district_l3, Kollective.Locations.PoliticalDistrict

    # Smallest local unit (optional)
    field :precinct, :string

    field :street_address, :string
    field :county, :string
    field :school_district_code, :string
    field :city_council_district_code, :string

    field :precinct_number, :string
    field :town_name, :string
    field :is_inside_city, :boolean, default: false
    field :applicable_office_ids, {:array, :string}, default: []

    # Internal City ID
    # field :city_id, :integer
    belongs_to :city, Kollective.Locations.City, foreign_key: :city_id
    # Display name
    field :city_name, :string

    # e.g., "California" or "CA"
    field :state, :string
    field :state_updated_at, :utc_datetime
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
    field :avatar_url, :string, default: "/default-avatar.jpg"
    field :cover_image_url, :string, default: "/default-banner-bg.jpg"

    # Virtual ranking score used by user search subqueries/order clauses.
    field :search_rank, :float, virtual: true

    # --- SOCIAL COUNTERS (Cached for performance) ---
    field :note_count, :integer, default: 0
    field :follower_count, :integer, default: 0
    field :following_count, :integer, default: 0

    # --- PERMISSIONS & ROLES ---
    field :is_admin, :boolean, default: false
    field :role, Ecto.Enum, values: [:user, :moderator, :admin], default: :user
    field :is_moderator, :boolean, default: false
    field :account_tier, :integer, default: 0
    field :metadata, :map, default: %{}
    field :origin_state, :string

    # --- PREFERENCES ---
    field :settings, :map, default: %{}
    field :email_notifications, :map, default: %{"digest" => false}
    field :date_of_birth, :date, virtual: true
    field :age, :integer
    field :show_age, :boolean, default: false
    field :birth_year, :integer

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
      foreign_key: :source_id,
      where: [type: "reblog_mute"]

    has_many :reblog_muted_users, through: [:reblog_mute_rels, :target]

    # Notification Mutes (Don't notify me when they interact)
    has_many :notification_mute_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "notification_mute"]

    has_many :notification_muted_users, through: [:notification_mute_rels, :target]

    # Endorsements (Featured users on your profile)
    has_many :endorsement_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "endorsement"]

    has_many :endorsed_users, through: [:endorsement_rels, :target]

    # Inverse Subscriptions (Requested follows / Private accounts)
    has_many :inv_sub_rels, Kollective.Accounts.UserRelationship,
      foreign_key: :source_id,
      where: [type: "inverse_subscription"]

    has_many :subscriber_users, through: [:inv_sub_rels, :target]

    # shadow-ban for aggressive spammers
    field :is_shadow_banned, :boolean, default: false

    # Users with true will bypass all keyword/weight checks
    field :is_exempt, :boolean, default: false

    field :is_verified, :boolean, default: false

    # Mode controllers -> "social_only" or "civic_active"
    field :experience_mode, :string, default: "social_only"

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
    # ["public", "unlisted", "local", "private", "direct", "list"]
    field :default_scope, :string, default: "public"

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

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :display_name,
      :is_verified,
      :identity_hash,
      :experience_mode,
      :account_tier,
      :metadata,
      :origin_state
    ])
    |> validate_required([:username, :identity_hash, :experience_mode])
    |> validate_inclusion(:experience_mode, ["social_only", "civic_active"])
    |> validate_length(:username, min: 2, max: 20)
    # FIX: Enforce Mastodon's default 30-character styling boundary constraint
    |> validate_length(:display_name, max: 30)
    |> unique_constraint(:username)
    |> default_display_name()
  end

  # Fallback helper function to keep your data layer consistent
  defp default_display_name(changeset) do
    if get_field(changeset, :type) == :organization do
      changeset
    else
      case get_change(changeset, :display_name) do
        nil ->
          # If no custom name was passed, mirror the username value automatically
          if username = get_change(changeset, :username) do
            put_change(changeset, :display_name, username)
          else
            changeset
          end

        _ ->
          changeset
      end
    end
  end

  def registration_changeset(user, attrs, opts \\ []) do
    attrs = normalize_attrs(attrs)

    user
    |> cast(attrs, [
      :email,
      :password,
      :display_name,
      :username,
      :date_of_birth,
      :country,
      :type,
      :representative_name
    ])
    |> default_display_name()
    |> validate_email(opts)
    |> validate_password(opts)
    |> validate_required([:username, :email])
    |> validate_length(:display_name, max: 100)
    |> validate_length(:username, min: 2, max: 20)
    |> validate_length(:representative_name, max: 100)
    |> validate_organization_attributes()
    # Example country codes
    |> validate_inclusion(:country, [
      "US",
      "CA",
      "GB",
      "AU",
      "DE",
      "FR",
      "JP",
      "MX",
      "ES",
      "IN",
      "AR",
      "BO",
      "BR",
      "CL",
      "CO",
      "VE",
      "UY",
      "PE",
      "PY"
    ])
    |> normalize_registration_age_fields()
    |> put_change(:is_confirmed, false)
  end

  defp normalize_registration_age_fields(changeset) do
    if get_field(changeset, :type) == :organization do
      changeset
      |> delete_change(:date_of_birth)
      |> delete_change(:age)
      |> delete_change(:birth_year)
    else
      today = Date.utc_today()
      birthday = get_change(changeset, :date_of_birth)
      age = get_change(changeset, :age)

      cond do
        birthday ->
          calculated_age = Date.diff(today, birthday) |> div(365)

          changeset
          |> put_change(:age, calculated_age)
          |> put_change(:birth_year, birthday.year)

        is_integer(age) and age >= 0 ->
          put_change(changeset, :birth_year, today.year - age)

        true ->
          changeset
      end
    end
  end

  defp validate_organization_attributes(changeset) do
    if get_field(changeset, :type) == :organization do
      validate_required(changeset, [:display_name])
    else
      changeset
    end
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    use_atom_keys? = Enum.any?(Map.keys(attrs), &is_atom/1)

    attrs
    |> maybe_copy_attr("displayname", :displayname, "display_name", :display_name, use_atom_keys?)
    |> maybe_copy_attr("org_name", :org_name, "display_name", :display_name, use_atom_keys?)
    |> maybe_copy_attr("org name", nil, "display_name", :display_name, use_atom_keys?)
    |> maybe_copy_attr("Org name", nil, "display_name", :display_name, use_atom_keys?)
    |> maybe_copy_attr(
      "organization_name",
      :organization_name,
      "display_name",
      :display_name,
      use_atom_keys?
    )
    |> maybe_copy_attr(
      "representative name",
      nil,
      "representative_name",
      :representative_name,
      use_atom_keys?
    )
    |> maybe_copy_attr(
      "Representative name",
      nil,
      "representative_name",
      :representative_name,
      use_atom_keys?
    )
    |> maybe_copy_attr(
      "representative_name",
      :representative_name,
      "representative_name",
      :representative_name,
      use_atom_keys?
    )
    |> maybe_copy_attr("birthday", :birthday, "date_of_birth", :date_of_birth, use_atom_keys?)
    |> maybe_copy_attr("show_birthday", :show_birthday, "show_age", :show_age, use_atom_keys?)
    |> normalize_registration_type(use_atom_keys?)
  end

  defp normalize_attrs(attrs), do: attrs

  defp normalize_registration_type(attrs, use_atom_keys?) do
    raw_type = Map.get(attrs, "type") || Map.get(attrs, :type)

    if raw_type != nil do
      normalized_type =
        case raw_type do
          type when type in ["organization", :organization] -> :organization
          _ -> :citizen
        end

      if use_atom_keys? do
        attrs
        |> Map.delete("type")
        |> Map.put(:type, normalized_type)
      else
        attrs
        |> Map.delete(:type)
        |> Map.put("type", to_string(normalized_type))
      end
    else
      attrs
    end
  end

  defp maybe_copy_attr(
         map,
         old_string_key,
         old_atom_key,
         new_string_key,
         new_atom_key,
         use_atom_keys?
       ) do
    val = Map.get(map, old_string_key) || (old_atom_key && Map.get(map, old_atom_key))

    if val != nil and Map.get(map, new_string_key) == nil and Map.get(map, new_atom_key) == nil do
      map =
        map
        |> Map.delete(old_string_key)
        |> then(fn m -> if old_atom_key, do: Map.delete(m, old_atom_key), else: m end)

      if use_atom_keys? do
        Map.put(map, new_atom_key, val)
      else
        Map.put(map, new_string_key, val)
      end
    else
      map
    end
  end

  # defp put_calculated_age(changeset) do
  #  case get_field(changeset, :date_of_birth) do
  #    %Date{} = dob ->
  #      age = calculate_age(dob)
  #      put_change(changeset, :age, age)
  #    _ ->
  #      changeset
  #  end
  # end

  # defp calculate_age(dob) do
  #  today = Date.utc_today()
  #  age = today.year - dob.year
  #
  #  # Adjust if the birthday hasn't happened yet this year
  #  if Date.compare(today, %{dob | year: today.year}) == :lt do
  #    age - 1
  #  else
  #    age
  #  end
  # end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    attrs = normalize_attrs(attrs)

    user
    |> cast(attrs, [:email, :username, :type, :display_name, :representative_name])
    |> default_display_name()
    |> put_default_username()
    |> update_change(:email, fn email ->
      if is_binary(email), do: String.downcase(email), else: email
    end)
    # 👈 Force email to lowercase before validation happens
    |> validate_email(opts)
    |> validate_length(:username, min: 2, max: 20)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:representative_name, max: 100)
    |> validate_organization_attributes()
    |> unique_constraint(:username)
  end

  defp put_default_username(changeset) do
    case get_field(changeset, :username) do
      nil ->
        email = get_field(changeset, :email)

        username =
          if email do
            email
            |> String.split("@")
            |> List.first()
            |> String.replace(~r/[^a-zA-Z0-9_]/, "")
            |> then(fn prefix -> "#{prefix}_#{System.unique_integer([:positive])}" end)
          else
            "user_#{System.unique_integer([:positive])}"
          end
          |> String.slice(0, 20)

        put_change(changeset, :username, username)

      _ ->
        changeset
    end
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
    change(user, confirmed_at: now, is_confirmed: true)
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

  # Profile Updates
  def profile_changeset(%__MODULE__{} = user, attrs) do
    attrs = normalize_profile_attrs(attrs)

    user
    # STRICT WHITE-LIST CASTING: Only allow modification of standard layout fields
    |> Ecto.Changeset.cast(attrs, [
      :display_name,
      :alias_name,
      :bio,
      :location,
      :avatar_url,
      :cover_image_url,
      :show_age,
      :accepts_chat_messages,
      :representative_name
    ])
    |> Ecto.Changeset.validate_length(:display_name, max: 100)
    |> Ecto.Changeset.validate_length(:representative_name, max: 100)
    # Traditional "Twitter-style" bio limit
    |> Ecto.Changeset.validate_length(:bio, max: 160)
    |> Ecto.Changeset.validate_length(:location, max: 255)
    # Ensure they are formatted as valid cloud storage urls before saving
    |> validate_url_prefix(:avatar_url)
    |> validate_url_prefix(:cover_image_url)
  end

  defp normalize_profile_attrs(attrs) when is_map(attrs) do
    avatar =
      Map.get(attrs, "avatar_url") || Map.get(attrs, "avatar") || Map.get(attrs, :avatar_url) ||
        Map.get(attrs, :avatar)

    cover =
      Map.get(attrs, "cover_image_url") || Map.get(attrs, "banner") || Map.get(attrs, "header") ||
        Map.get(attrs, "header_image") || Map.get(attrs, :cover_image_url) ||
        Map.get(attrs, :banner)

    name =
      Map.get(attrs, "display_name") || Map.get(attrs, "name") || Map.get(attrs, :display_name) ||
        Map.get(attrs, :name)

    representative =
      Map.get(attrs, "representative_name") || Map.get(attrs, "representative name") ||
        Map.get(attrs, :representative_name) || Map.get(attrs, :"representative name")

    attrs = if avatar != nil, do: Map.put_new(attrs, "avatar_url", avatar), else: attrs
    attrs = if cover != nil, do: Map.put_new(attrs, "cover_image_url", cover), else: attrs
    attrs = if name != nil, do: Map.put_new(attrs, "display_name", name), else: attrs

    attrs =
      if representative != nil,
        do: Map.put_new(attrs, "representative_name", representative),
        else: attrs

    attrs
  end

  defp normalize_profile_attrs(attrs), do: attrs

  defp validate_url_prefix(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if is_nil(value) or value == "" or
           String.starts_with?(value, ["http://", "https://", "/", "data:"]) do
        []
      else
        [{field, "must be a valid asset URL"}]
      end
    end)
  end

  def district_changeset(user, attrs) do
    user
    |> cast(attrs, [:state, :district_l1_id, :district_l2_id, :district_l3_id])
    |> validate_required([:state])
  end

  @doc """
  Changeset explicitly dedicated to mutating political district mappings.
  """
  def political_bounds_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :street_address,
      :county,
      :city_name,
      :school_district_code,
      :city_council_district_code,
      :district_l1_id,
      :district_l2_id,
      :district_l3_id,
      :origin_state,
      :state
    ])
    |> validate_required([:street_address, :district_l1_id])
  end

  def settings_changeset(user, attrs) do
    user
    # Add other settings here
    |> cast(attrs, [:auto_play_emails, :auto_play_gifs])
  end

  # Political Location Changeset used exclusively on the Settings Page
  def political_location_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :street_address,
      :country,
      :state,
      :state_updated_at,
      :metadata,
      :county,
      :city_id,
      :district_l1_id,
      :district_l2_id,
      :district_l3_id,
      :location
    ])
    # Guard: If street address is provided, validate complete 3-tier concentric district stack
    |> validate_complete_political_stack()
  end

  @doc """
  Extracts fuzzy coordinates `{lat, lng}` from user's stored location WKT.
  """
  def fuzzy_coordinates(%__MODULE__{location: "POINT(" <> _ = wkt}) do
    case Geo.WKT.decode(wkt) do
      {:ok, %Geo.Point{coordinates: {lng, lat}}} -> {lat, lng}
      _ -> {nil, nil}
    end
  end

  def fuzzy_coordinates(_), do: {nil, nil}

  defp validate_complete_political_stack(changeset) do
    street = get_field(changeset, :street_address)

    # Only validate district stack if user provided a street address
    if street && street != "" do
      l1 = get_field(changeset, :district_l1_id)
      l2 = get_field(changeset, :district_l2_id)
      l3 = get_field(changeset, :district_l3_id)

      case {l1, l2, l3} do
        {nil, _, _} ->
          add_error(changeset, :district_l1_id, "National boundary could not be resolved.")

        {_, nil, _} ->
          add_error(
            changeset,
            :district_l2_id,
            "State Upper Chamber boundary could not be resolved."
          )

        {_, _, nil} ->
          add_error(
            changeset,
            :district_l3_id,
            "Hyper-local Lower Chamber boundary could not be resolved."
          )

        _all_present ->
          changeset
      end
    else
      changeset
    end
  end
end

# create index(:user_relationships, [:source_id, :type, :target_id], unique: true)

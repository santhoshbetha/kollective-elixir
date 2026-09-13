defmodule Kollective.Posts.Post do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  alias Kollective.Notifications.Notification
  alias Kollective.Posts.{Like, Vote, PostAttachment, Posts}
  alias Kollective.Accounts.User
  alias Kollective.Polls.Poll
  alias Kollective.Hashtags.Hashtag

  @allowed_scopes [:local, :state, :country, :world]
  @visibilities ["public", "private", "unlisted", "direct"]

  @regular_limit 280
  @voice_limit 1000

  schema "posts" do
    # --- OWNERSHIP & CORE IDENTITY ---
    # Individual User / Organization Member (actual human who writes org posts)
    belongs_to(:author, User, foreign_key: :user_id)

    # Organization on whose behalf the post is written (if applicable)
    belongs_to(:organization, User, foreign_key: :organization_id)

    # 2. Cleanup for Discovery/Social Actions
    # This ensures that if a post is deleted, all related "liked", "reblogged",
    # or "replied" notifications are wiped from the DB.
    has_many :notifications, Notification, on_delete: :delete_all
    has_many :likes, Like

    # --- CONTENT & DISPLAY ---
    # HTML/Formatted content
    field :content, :string
    # Plain text (Searchable)
    field :text, :string
    # Content warning text
    field :sensitive, :boolean, default: false
    field :spoiler_text, :string
    # Short snippet
    field :summary, :string
    # Store as 'english', 'spanish', etc.
    field :language, :string, default: "english"

    # Virtual field: exists only in memory during the changeset
    field :language_override, :string, virtual: true
    field :content_type, :string, default: "text/html"

    # Store custom emoji shortcodes if you want :smile: support
    # Store a list of maps: [%{shortcode: "elixir", url: "https://..."}]
    field :emojis, {:array, :map}, virtual: true, default: []

    # Store reactions as: %{"🚀" => 5, "🔥" => 2}
    field :emoji_reactions, {:array, :map}, default: []

    # Track which app created the post (Web, Mobile, API)
    field :application_name, :string

    # Post Category: :post (standard) or :voice (urgent/protest)
    field :category, Ecto.Enum, values: [:post, :voice], default: :post

    # Trending score calculation column:
    field :trending_score, :float, default: 0.0

    # Optional: Level of urgency for Voice posts (1-5)
    field :urgency_level, :integer, default: 0

    # --- CATEGORIZATION & RANKING ---
    field :visibility, :string, default: "public"

    field :local, :boolean, default: true

    # Range: :local, :state, :country, :world
    field :target_scope, Ecto.Enum, values: @allowed_scopes, default: :local

    # The Geographic Anchor (Where it appears in "Local" tabs)
    field :origin_city_id, :integer
    field :origin_state, :string
    field :origin_country, :string, default: "US"
    field :origin_county, :string
    # federal_district
    field :origin_district_l1, :string
    # state_senate_district
    field :origin_district_l2, :string
    # state_district
    field :origin_district_l3, :string

    # Discovery/Voting / Quora-style Ranking
    field :upvotes_count, :integer, virtual: true, default: 0
    field :downvotes_count, :integer, virtual: true, default: 0
    field :score, :integer, virtual: true, default: 0

    # Engagement Cache
    field :likes_count, :integer, virtual: true, default: 0
    field :reblogs_count, :integer, virtual: true, default: 0
    field :replies_count, :integer, virtual: true, default: 0
    field :quotes_count, :integer, virtual: true, default: 0
    field :vote_data, :any, virtual: true

    # --- THREADING ---
    # Self-referential relationships for replies
    # These allow a post to know who its "boss" is
    # The Root/Thread ID
    # Self-Referential: The database guarantees that if a post has a root_post_id, that "root_post" must
    # actually exist in the posts table. If you try to delete the parent, the database can automatically
    # delete all children
    belongs_to :root_post, __MODULE__, foreign_key: :root_post_id
    # The Direct Parent
    belongs_to :in_reply_to_post, __MODULE__, foreign_key: :in_reply_to_id

    # These allow a post to see its "subordinates"
    # Retrieves all posts nested under this one (the "children")
    # foreign_key: By default, Ecto expects the "foreign key" for a "has_many" to be the name of the
    #              current module followed by _id (e.g., post_id). Since you used custom names like
    #              root_post_id and in_reply_to_id, you must tell the "has_many" side exactly which
    #              column to look for in the database.
    has_many :children, __MODULE__, foreign_key: :root_post_id
    # Retrieves all posts that were sent as a direct reply to this one
    # parent ID
    has_many :all_direct_replies, __MODULE__, foreign_key: :in_reply_to_id

    # Virtual field to hold the nested reply tree when fetching a thread
    # With this, Elixir can hold the nested replies without trying to save them to a database column
    # <--- Virtual field for the tree
    field :replies, {:array, :map}, virtual: true, default: []

    # Denormalized handle for "Replying to @user" display without extra joins
    field :in_reply_to_username, :string
    # Conversation ID for threading
    field :context, :string
    # For "Direct Messages" or "Group" specific threads
    field :direct_conversation_id, :integer

    # Quotes & Reblogs % Votes
    belongs_to :quote, __MODULE__, foreign_key: :quote_id
    field :quote_url, :string

    # The post being amplified
    belongs_to :reblog_of, __MODULE__, foreign_key: :reblog_of_id

    has_many :votes, Vote

    # Link to Hashtags via the join table string
    many_to_many :hashtags, Hashtag,
      join_through: "posts_hashtags",
      on_replace: :delete

    # For tagging users: [%{username: "alice", id: 1}, ...]
    # MISSING: List of tagged users
    field :mentions, {:array, :map}, default: []

    # To support "Voice" posts if they have a physical location/time
    field :event_data, :map

    # --- VIRTUAL (Per-User State) ---
    # These are populated during fetch based on the "current_user"
    field :liked, :boolean, virtual: true, default: false
    field :reblogged, :boolean, virtual: true, default: false
    field :muted, :boolean, virtual: true, default: false
    # Virtual field to hide specific loud threads for the current user
    field :thread_muted, :boolean, virtual: true, default: false
    field :bookmarked, :boolean, virtual: true, default: false
    field :pinned, :boolean, virtual: true, default: false

    # --- DATES & LIFECYCLE ---
    field :published_at, :utc_datetime
    field :edited_at, :utc_datetime
    field :edit_count, :integer, default: 0
    # Useful for temporary "Voice" posts
    field :expires_at, :utc_datetime
    field :pinned_at, :utc_datetime
    # For soft delete
    field :deleted_at, :utc_datetime

    # --- EXTENSIONS ---
    has_one(:poll, Poll)

    # Video transcoding can take several seconds for large files
    # "Upload Status" WebSocket
    #   1. Add a new field to track the processing status of the video.
    #   this allows your React frontend to show a "Processing..." state and disable interactions
    #   until the video is ready.
    field :processing_status, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed],
      default: :pending

    field :status, Ecto.Enum,
      values: [:published, :pending, :rejected, :appealed],
      default: :published

    # OpenGraph Link Preview Parameters (Stored directly on the row for fast O(1) feed reads)
    # "https://bbc.com..."
    field :link_url, :string
    # "Breaking News: AI Milestones reached"
    field :link_title, :string
    # "BBC coverage on newest technology shifts..."
    field :link_description, :string
    # Extracted OpenGraph image thumbnail URL
    field :link_preview_image, :string

    has_many :attachments, PostAttachment,
      foreign_key: :post_id,
      on_replace: :delete

    field :rejection_reason, :string
    field :rejected_at, :utc_datetime

    belongs_to :rejected_by, User, foreign_key: :rejected_by_id

    field :appeal_reason, :string
    field :appealed_at, :utc_datetime

    # Event Coordination logic for those "Voice" posts
    # Stores: %{meeting_time: "...", location_name: "...", lat: 0.0, lng: 0.0}
    field :coordination_data, :map, default: %{}

    field :data, :map, default: %{}
    field :metadata, :map, default: %{}
    timestamps()
  end

  @doc "Main changeset for creating/updating posts"
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :status,
      :category,
      :visibility,
      :sensitive,
      :reblog_of_id,
      :target_scope,
      :content,
      :text,
      :spoiler_text,
      :summary,
      :language,
      :language_override,
      :content_type,
      :urgency_level,
      :root_post_id,
      :in_reply_to_id,
      :in_reply_to_username,
      :quote_id,
      :quote_url,
      :link_url,
      :link_title,
      :link_description,
      :link_preview_image,
      :context,
      :direct_conversation_id,
      :replies_count,
      :quotes_count,
      :likes_count,
      :reblogs_count,
      :emojis,
      :emoji_reactions,
      :mentions,
      :application_name,
      :data,
      :metadata,
      :coordination_data,
      :published_at,
      :edited_at,
      :edit_count,
      :expires_at,
      :processing_status,
      :rejection_reason,
      :rejected_at,
      :rejected_by_id,
      :appeal_reason,
      :appealed_at,
      :origin_city_id,
      :origin_state,
      :origin_country,
      :origin_county,
      :origin_district_l1,
      :origin_district_l2,
      :origin_district_l3
    ])
    |> validate_required([:content, :status, :target_scope, :category])
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:target_scope, @allowed_scopes)
    |> validate_inclusion(:category, [:post, :voice])
    |> validate_number(:edit_count, greater_than_or_equal_to: 0)
    # --- Custom Dynamic Feature Pipings ---
    |> validate_content_length()
    |> validate_urgency_by_category()
    |> ensure_sensitive_if_spoiler()
    |> detect_and_set_language()
    # 🟢 FIXED: Replaced invalid cast_assoc with the helper method
    |> put_hashtags()
    # --- Media & Relationships ---
    |> cast_assoc(:attachments, with: &PostAttachment.changeset/2)
    |> validate_attachment_limit(4)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:root_post_id)
    |> foreign_key_constraint(:in_reply_to_id)
    |> validate_length(:content, max: 2000)
    |> validate_immutable_author(post)
  end

  defp validate_immutable_author(changeset, %__MODULE__{id: nil}) do
    changeset
  end

  defp validate_immutable_author(changeset, %__MODULE__{id: id}) when not is_nil(id) do
    if get_change(changeset, :user_id) do
      add_error(changeset, :user_id, "cannot be changed once post is created")
    else
      changeset
    end
  end

  # --- Private Processing Logic Helpers ---

  defp put_hashtags(changeset) do
    case get_change(changeset, :content) do
      nil ->
        changeset

      content ->
        # 1. Get the strings: ["elixir", "phoenix"]
        tag_names = Posts.extract_hashtags(content)

        # 2. Convert strings into Hashtag structs
        tags = Enum.map(tag_names, fn name -> Posts.get_or_create_hashtag(name) end)
        # 3. Associate them with the post
        put_assoc(changeset, :hashtags, tags)
    end
  end

  # Prioritizes the Manual Override from the UI, falls back to Automatic Detection if no override exists,
  # and finally uses the User Locale as the ultimate safety net.
  defp detect_and_set_language(changeset) do
    # 1. Gather all inputs
    content = get_change(changeset, :content)
    override = get_change(changeset, :language_override)

    # Fetch author locale (assumes author is preloaded or available in struct)
    user_locale = (get_field(changeset, :author) && get_field(changeset, :author).locale) || "en"

    cond do
      # Priority 1: User manually selected a language in the React dropdown
      not is_nil(override) and override != "" ->
        put_change(changeset, :language, map_to_postgres_lang(override))

      # Priority 2: Automatically detect if content exists
      not is_nil(content) and content != "" ->
        supported_langs = [:english, :spanish, :french, :german]

        # Use Lingua to detect from your supported subset
        detected_language =
          Lingua.detect(content, builder_option: :with_languages, languages: supported_langs)

        # Use detected result; if Lingua is unsure, fall back to user's default locale
        # 🔄 FIX: Use a case statement to safely unwrap the Lingua result tuple typings
        final_lang =
          case detected_language do
            {:ok, language_atom} ->
              language_atom

            {:error, _reason} ->
              # If Lingua is unsure or encounters an error, safely fall back to user's locale
              user_locale
          end

        put_change(changeset, :language, map_to_postgres_lang(final_lang))

      # Priority 3: Fallback (Empty content or no detection)
      is_nil(get_field(changeset, :language)) ->
        put_change(changeset, :language, map_to_postgres_lang(user_locale))

      true ->
        changeset
    end
  end

  # Lingua returns atoms like :english, :spanish, etc.
  # Ensure your mapping handles both Atoms (from Lingua) and Strings (from Override/Locale)
  defp map_to_postgres_lang(lang) when lang in [:english, "en", "english"], do: "english"
  defp map_to_postgres_lang(lang) when lang in [:spanish, "es", "spanish"], do: "spanish"
  defp map_to_postgres_lang(lang) when lang in [:french, "fr", "french"], do: "french"
  defp map_to_postgres_lang(lang) when lang in [:german, "de", "german"], do: "german"
  defp map_to_postgres_lang(_), do: "simple"

  defp ensure_sensitive_if_spoiler(changeset) do
    case get_field(changeset, :spoiler_text) do
      nil -> changeset
      "" -> changeset
      _ -> put_change(changeset, :sensitive, true)
    end
  end

  defp validate_content_length(changeset) do
    category = get_field(changeset, :category)
    limit = if category == :voice, do: @voice_limit, else: @regular_limit

    # Note: If you want to use the Mastodon link discount weights helper,
    # swap validate_length below with: validate_mastodon_length(changeset, :text, limit)
    validate_length(changeset, :text,
      max: limit,
      message: "for #{category} posts cannot exceed #{limit} characters"
    )
  end

  # Custom validation: ensure urgency is only set for voice posts
  defp validate_urgency_by_category(changeset) do
    category = get_field(changeset, :category)

    if category == :post && (get_field(changeset, :urgency_level) || 0) > 0 do
      add_error(changeset, :urgency_level, "cannot be set for standard posts")
    else
      changeset
    end
  end

  defp validate_attachment_limit(changeset, max) do
    attachments =
      case get_change(changeset, :attachments) do
        nil ->
          case changeset.data.attachments do
            %Ecto.Association.NotLoaded{} -> []
            list -> list || []
          end

        list ->
          list || []
      end

    if length(attachments) > max do
      add_error(changeset, :attachments, "cannot have more than #{max} files")
    else
      changeset
    end
  end
end

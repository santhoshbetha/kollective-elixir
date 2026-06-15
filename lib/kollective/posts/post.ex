defmodule Kollective.Posts.Post do
  use Kollective.Schemas.Schema

  alias Kollective.Notifications.Notification

  @allowed_scopes [:local, :state, :country, :world]
  @visibilities ["public", "private", "unlisted"]

  @regular_limit 280
  @voice_limit 1000

  schema "posts" do
    # --- OWNERSHIP & CORE IDENTITY ---
    # Individual User/ Orgamization Member (actual human who writes org posts)
    belongs_to(:author, Kollective.Accounts.User, foreign_key: :user_id)

    # If this is set, the post is an "Organization Post"
    belongs_to(:organization, Kollective.Accounts.Organization)

    # 2. Cleanup for Discovery/Social Actions
    # This ensures that if a post is deleted, all related "liked", "reblogged",
    # or "replied" notifications are wiped from the DB.
    has_many :notifications, Notification, on_delete: :delete_all

    has_many :likes, Kollective.Posts.Like

    # ActivityPub/External Identifier
    field(:uri, :string)
    # Permalinks
    field(:url, :string)

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
    field :language, :string,  default: "english" # Store as 'english', 'spanish', etc.

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

    # Optional: Level of urgency for Voice posts (1-5)
    field :urgency_level, :integer, default: 0

    # --- CATEGORIZATION & RANKING ---
    field :visibility, :string, default: "public"

    field :local, :boolean, default: true

    # Range: :local, :state, :country, :world
    field :target_scope, Ecto.Enum, values: [:local, :state, :country, :world], default: :local

    # The Geographic Anchor (Where it appears in "Local" tabs)
    field :origin_city_id, :integer
    field :origin_state, :string

    field :origin_country, :string, default: "US"

    # federal_district
    field :district_l1, :string
    # state_senate_district
    field :district_l2, :string
    # state_district
    field :district_l3, :string

    # Discovery/Voting / Quora-style Ranking
    field :upvotes_count,   :integer, virtual: true, default: 0
    field :downvotes_count, :integer, virtual: true, default: 0
    field :score,           :integer, virtual: true, default: 0

    # Engagement Cache
    # Virtual field to hold the aggregate count from the DB
    field :likes_count,   :integer, virtual: true, default: 0
    field :reblogs_count, :integer, virtual: true, default: 0
    field :replies_count, :integer, virtual: true, default: 0
    field :quotes_count,  :integer, virtual: true, default: 0

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
    has_many :all_direct_replies, __MODULE__, foreign_key: :in_reply_to_id

    # Virtual field to hold the nested reply tree when fetching a thread
    # With this, Elixir can hold the nested replies without trying to save them to a database column
    field :replies, {:array, :map}, virtual: true, default: [] # <--- Virtual field for the tree

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

    has_many :votes, Kollective.Posts.Vote

    # Link to Hashtags via the join table string
    many_to_many :hashtags, Kollective.Hashtags.Hashtag, join_through: "posts_hashtags", on_replace: :delete

    # For tagging users: [%{username: "alice", id: 1}, ...]
    # MISSING: List of tagged users
    field :mentions, {:array, :map}, default: []

    # To support your "Voice" posts if they have a physical location/time
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
    # Useful for temporary "Voice" posts
    field :expires_at, :utc_datetime
    field :pinned_at, :utc_datetime
    # For soft delete
    field :deleted_at, :utc_datetime

    # --- EXTENSIONS ---
    # has_one(:video, Kollective.Videos.Video)
    has_one(:poll, Kollective.Polls.Poll)

    has_many :attachments, Kollective.Posts.PostAttachment, on_replace: :delete

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

    field :rejection_reason, :string
    field :rejected_at, :utc_datetime

    belongs_to :rejected_by, Kollective.Accounts.User, foreign_key: :rejected_by_id

    field :appeal_reason, :string
    field :appealed_at, :utc_datetime

    # Event Coordination logic for those "Voice" posts
    # Stores: %{meeting_time: "...", location_name: "...", lat: 0.0, lng: 0.0}
    field :coordination_data, :map, default: %{}

    field :data, :map, default: %{}
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changesetX(post, attrs) do
    post
    |> cast(attrs, [:content, :author_id, :parent_id, :in_reply_to_id, :language_override])
    |> cast_assoc(:poll, with: &Kollective.Polls.Poll.changeset/2)
    |> validate_required([:content, :author_id]) # author is usually mandatory
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:in_reply_to_id)
    |> validate_mastodon_length(:content, 500)
    # Call the extractor here
    |> put_hashtags()
    |> detect_and_set_language() # <--- New helper
    # Mastodon logic: If there's a warning, the content is sensitive
    |> ensure_sensitive_if_spoiler()
  end

  defp put_hashtags(changeset) do
    case get_change(changeset, :content) do
      nil -> changeset
      content ->
        # 1. Get the strings: ["elixir", "phoenix"]
        tag_names = Kollective.Posts.Posts.extract_hashtags(content)

        # 2. Convert strings into Hashtag structs
        tags = Enum.map(tag_names, fn name ->
          Kollective.Posts.Posts.get_or_create_hashtag(name)
        end)

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
        detected_language = Lingua.detect(content,
          builder_option: :with_languages,
          languages: supported_langs
        )

        # Use detected result; if Lingua is unsure, fall back to user's default locale
        final_lang = if detected_language, do: detected_language, else: user_locale
        put_change(changeset, :language, map_to_postgres_lang(final_lang))

      # Priority 3: Fallback (Empty content or no detection)
      true ->
        put_change(changeset, :language, map_to_postgres_lang(user_locale))
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

  # This function finds every URL in the content, subtracts its actual length from the total,
  # and adds back 23 characters for each.
  # Mentions (like @username@domain.com) are also special: only the username part counts toward the
  # character limit; the @domain part is free. This encourages cross-server communication without punishing
  # users for long instance names.
  defp validate_mastodon_length(changeset, field, max_limit) do
    validate_change(changeset, field, fn _, content ->
      if content do
        # 1. Regex for URLs (http/https)
        url_regex = ~r/https?:\/\/[^\s]+/
        # 2. Regex for Mentions (@user@domain.com)
        # We capture the full mention to calculate the "discount"
        mention_regex = ~r/@[a-z0-9_]+(@[a-z0-9\.\-]+)/i

        # Calculate URL discount
        urls = Regex.scan(url_regex, content) |> List.flatten()
        url_adjustment = Enum.reduce(urls, 0, fn url, acc ->
          acc + (String.length(url) - 23)
        end)

        # Calculate Mention discount (subtract the @domain part)
        mentions = Regex.scan(mention_regex, content)
        mention_adjustment = Enum.reduce(mentions, 0, fn [_full_mention, domain_part], acc ->
          acc + String.length(domain_part)
        end)

        # Final Mastodon weight
        final_length = String.length(content) - url_adjustment - mention_adjustment

        if final_length > max_limit do
          [{field, "is too long (Count: #{final_length}/#{max_limit})"}]
        else
          []
        end
      else
        []
      end
    end)
  end


  @doc "Main changeset for creating/updating posts"
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      # Core Identity
      :user_id, :organization_id, :status, :category, :visibility, :target_scope,
      # Content
      :content, :text, :spoiler_text, :summary, :language, :content_type, :urgency_level,
      # Threading & Relations
      :parent_id, :in_reply_to_id, :in_reply_to_username,
      :quote_id, :quote_url, :reblog_id, :context, :direct_conversation_id,
      # Engagement & Counters (Usually updated via context, but castable for migrations/sync)
      :replies_count, :quotes_count, :likes_count, :reblogs_count,
      # Rich Data (JSONB)
      :emojis, :emoji_reactions, :mentions, :application_name, :data, :metadata,
      # Lifecycle
      :published_at, :expires_at, :processing_status
    ])
    # --- Validations ---
    |> validate_required([:content, :status, :target_scope, :category])
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:target_scope, @allowed_scopes)
    |> validate_inclusion(:category, [:post, :voice])
    # --- Custom Logic from your existing code ---
    |> validate_content_length()
    |> validate_urgency_by_category()
    # --- Media ---
    # This maps 'attachments' from your React FormData to the PostAttachment schema
    |> cast_assoc(:attachments, with: &Kollective.Posts.PostAttachment.changeset/2)
    |> validate_attachment_limit(4)
    # --- Relations ---
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:parent_id)
    |> validate_length(:content, max: 2000)
    |> cast_assoc(:hashtags)
  end

  defp validate_content_length(changeset) do
    category = get_field(changeset, :category)

    # We validate the 'text' field (plain text) to ensure
    # HTML tags in 'content' don't count against the user's limit.
    limit = if category == :voice, do: @voice_limit, else: @regular_limit

    validate_length(changeset, :text,
      max: limit,
      message: "for #{category} posts cannot exceed #{limit} characters"
    )
  end

  # Custom validation: ensure urgency is only set for voice posts
  defp validate_urgency_by_category(changeset) do
    category = get_field(changeset, :category)
    if category == :post && get_field(changeset, :urgency_level) > 0 do
      add_error(changeset, :urgency_level, "cannot be set for standard posts")
    else
      changeset
    end
  end

  defp validate_attachment_limit(changeset, max) do
    attachments = get_field(changeset, :attachments) || []
    if length(attachments) > max do
      add_error(changeset, :attachments, "cannot have more than #{max} files")
    else
      changeset
    end
  end
end

# Indices are CRITICAL for performance in self-referential tables
# create index(:posts, [:root_post_id])
# create index(:posts, [:in_reply_to_id])
# create index(:posts, [:reblog_of_id])

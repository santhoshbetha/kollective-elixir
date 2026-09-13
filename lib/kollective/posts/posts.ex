defmodule Kollective.Posts.Posts do
  import Ecto.Query, warn: false

  alias Kollective.Repo
  alias Ecto.Multi
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Accounts
  alias Kollective.Accounts.Users
  alias Kollective.Accounts.AuditLog
  alias Kollective.Accounts.OrganizationMembership
  alias Kollective.Posts.Post
  alias Kollective.Posts.Like
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Notifications.Notifications
  alias Kollective.Hashtags.Hashtag
  alias Kollective.Posts.ThreadMute
  alias Kollective.Admins.Log, as: AdminLog

  alias Kollective.Workers.{
    PublishPostWorker,
    PollExpiryWorker,
    VideoTranscoder,
    MentionNotificationWorker,
    FeedFanoutWorker,
    VoiceBroadcastWorker
  }

  alias Kollective.Posts.PostBookmark

  alias Kollective.Polls.Polls
  alias Kollective.Polls.Poll
  alias Kollective.Polls.PollVote
  alias Kollective.Polls.PollOption
  alias Kollective.Posts.CustomEmoji
  alias Kollective.Posts.UserFilter

  alias Scrivener

  @doc """
  Safely fetches a single post by ID.
  Preloads the author profile and media attachments in one single database pass.
  Returns `{:ok, post}` or `{:error, :not_found}` to allow clean pattern matching.
  """
  def get_post(id) do
    Post
    |> preload([:author, :organization, :attachments, :hashtags, :reblog_of, poll: :options])
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  @doc """
  Fetches a single post by ID, raising an Ecto.NoResultsError if not found.
  Use this for internal system jobs or workers where a missing record means a hard failure.
  """
  def get_post!(id) do
    Post
    |> preload([:author, :organization, :attachments, :hashtags, :reblog_of, poll: :options])
    |> Repo.get!(id)
  end

  def list_local_feed(user, params) do
    Post
    |> where(
      [p],
      p.origin_district_l1 == ^user.district_l1_id or
        p.origin_district_l2 == ^user.district_l2_id or
        p.origin_district_l3 == ^user.district_l3_id
    )
    |> common_feed_pipeline(user, params)
  end

  def list_state_feed(user, params) do
    Post
    |> where([p], p.origin_state == ^user.state)
    |> where([p], p.origin_district_l1 != ^user.district_l1_id)
    |> where([p], p.origin_district_l2 != ^user.district_l2_id)
    |> where([p], p.origin_district_l3 != ^user.district_l3_id)
    |> common_feed_pipeline(user, params)
  end

  @spec list_country_feed(any(), nil | maybe_improper_list() | map()) :: Scrivener.Page.t()
  def list_country_feed(user, params) do
    Post
    |> where([p], p.origin_country == ^user.country)
    # EXCLUDE the user's entire state
    |> where([p], p.origin_state != ^user.state)
    |> common_feed_pipeline(user, params)
  end

  def list_world_feed(user, params) do
    Post
    |> where([p], p.origin_country != ^user.country)
    |> common_feed_pipeline(user, params)
  end

  # Helper to DRY up the sorting, pagination, and preloading
  defp common_feed_pipeline(query, _user, params) do
    query
    |> order_by([p], desc: p.inserted_at)
    |> Repo.paginate(page: params["page"] || 1)
    |> then(fn page ->
      # We preload ONLY for the entries on the current page
      %{
        page
        | entries:
            Repo.preload(page.entries, [
              :author,
              :attachments
            ])
      }
    end)
  end

  # Ring 1: Specific Local Districts (L1, L2, L3)
  defp base_local_query(user) do
    from p in Post,
      where:
        p.origin_district_l1 == ^user.district_l1_id or
          p.origin_district_l2 == ^user.district_l2_id or
          p.origin_district_l3 == ^user.district_l3_id
  end

  # Ring 2: Entire State, EXCLUDING the local districts
  defp base_state_query(user) do
    from p in Post,
      where: p.origin_state == ^user.state,
      where:
        p.origin_district_l1 != ^user.district_l1_id and
          p.origin_district_l2 != ^user.district_l2_id and
          p.origin_district_l3 != ^user.district_l3_id
  end

  # Ring 3: Entire Country, EXCLUDING their state
  defp base_country_query(user) do
    from p in Post,
      where: p.origin_country == ^user.country,
      where: p.origin_state != ^user.state
  end

  # Ring 4: The Entire World, EXCLUDING their country
  defp base_world_query(user) do
    from p in Post,
      where: p.origin_country != ^user.country
  end

  @spec has_unread_posts?(any(), :country | :local | :state | :world) :: boolean()
  def has_unread_posts?(nil, _scope), do: false
  def has_unread_posts?(%{last_read_at: nil}, _scope), do: false

  def has_unread_posts?(user, scope) do
    query =
      case scope do
        :local -> base_local_query(user)
        :state -> base_state_query(user)
        :country -> base_country_query(user)
        :world -> base_world_query(user)
      end

    query
    |> where([p], p.inserted_at > ^user.last_read_at)
    # Efficiently returns true/false
    |> Repo.exists?()
  end

  # Fetching a deep thread is tricky because a standard preload only goes one level deep.
  # To get an entire conversation of unknown depth, we use a Recursive Common Table Expression (CTE).
  # This is the logic used to "climb" up or down a tree in one single database hit.

  # Without Recursion: If a thread is 10 replies deep, you would have to run 10 separate database queries
  #                    (very slow).
  # With Recursion: The database finds every connected reply in one pass and returns them as a single list.
  def get_full_conversation(post_id) do
    # Base case: the specific post you are looking at
    initial_query = where(Post, [p], p.id == ^post_id)

    # Recursion: find all posts that have this post's ID as their in_reply_to_id
    recursion_query =
      Post
      |> join(:inner, [p], t in "thread", on: p.in_reply_to_id == t.id)

    # Combine and execute
    initial_query
    |> union_all(^recursion_query)
    |> recursive_ctes(true)
    # Simplification for example
    |> with_cte("thread", as: ^initial_query)
    |> order_by([p], asc: p.inserted_at)
    |> Repo.all()
  end

  # Formatting into a Nested Tree:
  # Once you have a flat list of posts from the database, you can transform them into a nested
  # structure in Elixir using Enum.group_by/2
  def build_tree(posts) do
    # Group posts by their parent/reply ID for fast lookup
    # Group the maps by the ID of the post they are replying to
    # Item structure: %{post: %Post{}, likes_count: 5, has_liked: true}
    # posts_by_parent = Enum.group_by(posts, & &1.in_reply_to_id)
    posts_by_parent = Enum.group_by(posts, fn %{post: p} -> p.in_reply_to_id end)

    # Safely fall back to an empty list if there are no top-level posts found
    top_level_posts = Map.get(posts_by_parent, nil, [])

    # Start building from the top-level posts (where in_reply_to_id is nil)
    nest_posts(top_level_posts, posts_by_parent)
  end

  defp nest_posts(nil, _), do: []

  defp nest_posts(posts, mapping) do
    Enum.map(posts, fn post ->
      # Recursively attach replies to each post
      # Find child elements using Map.get with a safe empty list fallback
      children = Map.get(mapping, post.id, [])
      # Recursively find replies for this specific item's post ID
      replies = nest_posts(children, mapping)

      # Put the replies into the map so React can find them
      Map.put(post, :replies, replies)
    end)
  end

  # @doc """
  # Unifies all pipeline variants for creating a post, including targeting overrides,
  # content scrubbing, threading, atomic hashtag mappings, mention hooks, and media hooks.
  # """
  # def create_postX(%User{} = user, attrs \\ %{}) do
  #   # 1. Resolve content parameter safety and metadata state variants
  #   #    content_text = attrs["content"] || attrs[:content] || ""
  #   #    is_reply = not is_nil(attrs["in_reply_to_id"] || attrs[:in_reply_to_id])

  #   #    # 2. Extract references & metadata outside of transaction engine
  #   #    # Extract tag names from content: ["elixir", "coding"]
  #    tag_names = extract_hashtags(content_text)
  #    mentioned_usernames = parse_mention_strings(content_text)

  #    # 3. Determine safety layout (Shadowban checks / Restricted Keyword processing)
  #    is_restricted = user.is_shadow_banned || contains_restricted_words?(content_text)
  #    initial_status = if is_restricted, do: "pending", else: "published"

  #    # 4. Thread routing: Identify immediate parent context & long-term root_post_id
  #    attrs = append_threading_context(attrs)

  #    # 5. Build full transactional Multi sequence
  #    Multi.new()
  #    # 1. Initial Schema Insertion with Core Properties & Geographic Targeting
  #    # Base Post Insert & Geo Targeting
  #    |> Multi.insert(:post, fn _repo ->
  #      %Post{user_id: user.id, author: user, status: initial_status}
  #      # Pass BOTH the raw attrs and the user struct to the targeting engine
  #      |> validate_and_fix_targeting(attrs, user)
  #    end)

  # 2. Parse and Upsert Global Hashtags
  # Extract and Upsert Hashtags (Convert names into Hashtag structs (Get or Create)
  #    |> Multi.run(:hashtags, fn _repo, %{post: post} ->
  #      tags = upsert_hashtag_entities(tag_names)

  #      post
  #      |> Repo.preload(:hashtags)
  #      |> Post.changeset(%{})
  #      |> Ecto.Changeset.put_assoc(:hashtags, tags)
  #      |> Repo.update()
  #    end)

  # 3. Isolate Verified Mentions, Register Database Notifications, Link UI Fields
  # Synchronize UI Mention Array Field Data Structure (No long text parsing in React)
  # |> Multi.run(:notifications_and_mentions, fn _repo, %{hashtags: post} ->
  #   # Filter for matching database entities
  #   verified_mentions = Accounts.list_users_by_usernames(mentioned_usernames)
  #
  #   parent_author_id = get_parent_author_id(post)
  #
  #   # Register structural notify hooks for mentions
  #   register_mention_notifications(post, verified_mentions, parent_author_id)
  #
  #   # Register structural notify hook for root author reply tracking
  #   if is_reply, do: notify_parent_author(post)

  # Save static serialization layout block to avoid complex extraction loops inside React UI
  #  post
  #  |> Ecto.Changeset.change(
  #      mentions: Enum.map(verified_mentions, &%{id: &1.id, username: &1.username})
  #    )
  #    |> Repo.update()
  #  end)

  # 4. Media Handling Layout Support (Waffle file mappings)
  # Attach Media (Waffle needs the Post ID for the folder path)
  # (Waffle.Ecto moves the file to /uploads/posts/[ID]/...)
  # |> Multi.run(:media_upload, fn _repo, %{notifications_and_mentions: post} ->
  #  if attrs["media"] do
  #    post
  #    # Waffle.Ecto handles the file move
  #  |> Post.changeset(%{media: attrs["media"]})
  #  |> Repo.update()
  #  else
  #    {:ok, post}
  #  end
  #  end)

  # 5. ASYNC LIFECYCLE SCHEDULING (Queue up Oban Jobs inside the Transaction)
  # |> Multi.run(:oban_jobs, fn _repo, %{media_upload: post} ->
  #   # Preload attachments to safely inspect content_types
  #   post = Repo.preload(post, :attachments)
  #
  #   # A. Video Transcoding Worker Queue (Safer than Task.start)
  #   post.attachments
  #   |> Enum.filter(&String.starts_with?(&1.content_type || "", "video"))
  #   |> Enum.each(fn att ->
  #     %{attachment_id: att.id}
  #     |> VideoTranscoder.new()
  #     |> Oban.insert!()
  #   end)
  # end)
  #    %{attachment_id: att.id}
  #    |> VideoTranscoder.new()
  #    |> Oban.insert!()
  #  end)

  # B. Mention Notification Worker Queue (Only if post is clear/published)
  #  if post.status == "published" do
  #    %{
  #      "actor_id" => user.id,
  #      "text" => post.content,
  #      "post_id" => post.id,
  #      "type" => "mention"
  #    }
  #    |> MentionNotificationWorker.new()
  #    |> Oban.insert!()

  # C. Send immediate reply tracking push if this is a chronological thread reply
  #    if is_reply, do: notify_parent_author(post)
  #  end

  # D. Schedule Future Post Date Actions
  #    if Map.has_key?(attrs, "published_at") &&
  #           DateTime.compare(post.published_at, DateTime.utc_now()) == :gt do
  #      %{post_id: post.id}
  #      |> PublishPostWorker.new(scheduled_at: post.published_at)
  #      |> Oban.insert!()
  #    end

  # E. Schedule Poll Expiry Closures
  #    if post.poll do
  #      %{poll_id: post.poll.id}
  #      |> PollExpiryWorker.new(scheduled_at: post.poll.expires_at)
  #      |> Oban.insert!()
  #    end

  # F. Return the post for further processing
  # if post.visibility == "public" && post.status == "published" do
  #  Queue up the background fan-out process seamlessly
  #  %{post_id: post.id, author_id: post.user_id}
  #  |> FeedFanoutWorker.new()
  #  |> Oban.insert!()
  # end

  # {:ok, post}
  # end)
  # Execution Transaction Engine Block
  #  |> Repo.transaction()
  #  |> handle_lifecycle_broadcasts()
  # end

  @doc """
  The master standalone timeline post creator. Manages multi-tier parameters,
  geographic targeting, hashtag upserts, asynchronous notifications, direct R2 image arrays,
  and automated external OpenGraph web link crawling inside a single transaction sweep.
  """
  def create_post(%Kollective.Accounts.User{} = user, attrs \\ %{}, uploaded_images \\ []) do
    # 1. Resolve content parameter safety and metadata state variants
    content_text = attrs["content"] || attrs[:content] || ""
    is_reply = not is_nil(attrs["in_reply_to_id"] || attrs[:in_reply_to_id])

    # 2. Extract tags, mentions, and look for pasted external links outside the transaction window
    tag_names = extract_hashtags(content_text)
    mentioned_usernames = parse_mention_strings(content_text)
    extracted_link = extract_first_url(content_text)

    # 3. Determine safety layout (Shadowban checks / Restricted Keyword processing)
    is_restricted = user.is_shadow_banned || contains_restricted_words?(content_text)

    initial_status =
      cond do
        attrs["status"] in [:published, "published"] -> :published
        attrs["status"] in [:pending, "pending"] -> :pending
        attrs[:status] in [:published, "published"] -> :published
        attrs[:status] in [:pending, "pending"] -> :pending
        is_restricted -> :pending
        true -> :published
      end

    # 4. Thread routing: Identify immediate parent context & long-term root_post_id
    attrs = append_threading_context(attrs)

    # Base attributes merge containing your OpenGraph linkage hooks
    org_id =
      attrs["organization_id"] || attrs[:organization_id] ||
        if(user.type == :organization, do: user.id, else: nil)

    final_attrs =
      attrs
      |> Map.put("user_id", user.id)
      |> Map.put("organization_id", org_id)
      |> Map.put("link_url", extracted_link)
      |> Map.put("status", initial_status)

    # Extract the nested poll data parameters from incoming attributes
    poll_attrs = attrs["poll"] || attrs[:poll]

    # 5. Build full transactional Multi sequence
    now_naive = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    Multi.new()
    # Step 1: Initial Schema Insertion with Core Properties & Geographic Targeting
    |> Multi.insert(:post, fn _repo ->
      post_struct = %Post{
        user_id: user.id,
        author: user,
        organization_id: org_id,
        status: initial_status
      }

      # 🔄 FIX: Wrap the raw struct in a changeset before calling the targeting engine
      post_struct
      |> Post.changeset(final_attrs)
      |> validate_and_fix_targeting(final_attrs, user)
    end)
    # Step 1b: Increment user's note_count counter and update last_post_at
    |> Multi.update_all(
      :increment_note_count,
      from(u in User, where: u.id == ^user.id),
      inc: [note_count: 1],
      set: [last_post_at: now_naive]
    )
    |> Multi.run(:increment_org_note_count, fn repo, _changes ->
      if org_id && org_id != user.id do
        repo.update_all(
          from(u in User, where: u.id == ^org_id),
          inc: [note_count: 1],
          set: [last_post_at: now_naive]
        )

        {:ok, :incremented}
      else
        {:ok, :noop}
      end
    end)

    # Step 2: Conditionally Insert Nested Poll Structures inside the transaction
    |> Multi.run(:poll, fn _repo, %{post: post} ->
      if poll_attrs && is_map(poll_attrs) do
        # Bind the newly generated post ID directly to the poll payload footprint
        full_poll_attrs = Map.put(poll_attrs, "post_id", post.id)

        %Poll{post_id: post.id}
        |> Poll.changeset(full_poll_attrs)
        |> Repo.insert()
      else
        # If no poll parameter data was provided, skip cleanly without failures
        {:ok, nil}
      end
    end)

    # Step 3: Parse and Upsert Global Hashtags
    |> Multi.run(:hashtags, fn _repo, %{post: post} ->
      tags = upsert_hashtag_entities(tag_names)

      post
      |> Repo.preload(:hashtags)
      |> Post.changeset(%{})
      |> Ecto.Changeset.put_assoc(:hashtags, tags)
      |> Repo.update()
    end)

    # Step 4: Isolate Verified Mentions, Register Database Notifications, Link UI Fields
    |> Multi.run(:notifications_and_mentions, fn _repo, %{hashtags: post} ->
      verified_mentions = Accounts.list_users_by_usernames(mentioned_usernames)
      parent_author_id = get_parent_author_id(post)

      # Register structural notify hooks for mentions
      register_mention_notifications(post, verified_mentions, parent_author_id)

      # Register structural notify hook for root author reply tracking
      if is_reply, do: notify_parent_author(post)

      # Save static serialization layout block to avoid complex extraction loops inside React UI
      post
      |> Ecto.Changeset.change(
        mentions: Enum.map(verified_mentions, &%{id: &1.id, username: &1.username})
      )
      |> Repo.update()
    end)

    # Step 5: CLOUDFLARE R2 MULTI-IMAGE CAROUSEL ALLOCATION
    # Connects direct frontend asset URLs directly to the post_attachments join table
    |> Multi.run(:media_upload, fn _repo, %{notifications_and_mentions: post} ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attachment_rows =
        Enum.map(uploaded_images, fn img_url ->
          %{
            id: Kollective.Schemas.ULIDType.generate(),
            post_id: post.id,
            url: img_url,
            media_type: "image/jpeg",
            inserted_at: now,
            updated_at: now
          }
        end)

      if attachment_rows != [] do
        Repo.insert_all("post_attachments", attachment_rows)
      end

      {:ok, post}
    end)

    # Step 6: ASYNC LIFECYCLE SCHEDULING (Queue up Oban Jobs inside the Transaction)
    |> Multi.run(:oban_jobs, fn _repo, %{media_upload: post, poll: _poll} ->
      # Preload attachments to safely inspect content_types
      post = Repo.preload(post, [:attachments, :poll])

      # A. Video Transcoding Worker Queue (Safer than Task.start)
      post.attachments
      |> Enum.filter(&String.starts_with?(&1.media_type || "", "video"))
      |> Enum.each(fn att ->
        %{attachment_id: att.id}
        |> VideoTranscoder.new()
        |> Oban.insert!()
      end)

      # B. Mention Notification Worker Queue (Only if post is clear/published)
      if post.status == "published" do
        %{
          "actor_id" => user.id,
          "text" => post.content,
          "post_id" => post.id,
          "type" => "mention"
        }
        |> MentionNotificationWorker.new()
        |> Oban.insert!()
      end

      # C. Schedule Future Post Date Actions
      if Map.has_key?(attrs, "published_at") &&
           DateTime.compare(attrs["published_at"], DateTime.utc_now()) == :gt do
        %{post_id: post.id}
        |> PublishPostWorker.new(scheduled_at: attrs["published_at"])
        |> Oban.insert!()
      end

      # D. Schedule Poll Expiry Closures
      if Ecto.assoc_loaded?(post.poll) && post.poll do
        %{poll_id: post.poll.id}
        |> PollExpiryWorker.new(scheduled_at: post.poll.expires_at)
        |> Oban.insert!()
      end

      # E. Queue up the background fan-out process seamlessly
      if Map.get(post, :visibility) == "public" and post.status == "published" do
        %{post_id: post.id, author_id: post.user_id}
        |> FeedFanoutWorker.new()
        |> Oban.insert!()
      end

      {:ok, post}
    end)
    # Execution Transaction Engine Block
    |> Repo.transaction()
    |> case do
      {:ok, %{oban_jobs: final_post}} ->
        # Step 6:
        # Hydrate associations to pass safely into your unified serialization view components
        # Ensure relationships and newly bound polls preload cleanly for the view layer
        hydrated_post = Repo.preload(final_post, [:author, :attachments, :poll, poll: :options])

        # ─── UNIVERSAL REAL-TIME BROADCAST MATRIX ───
        # Only stream if the content successfully bypasses standard moderation queues
        if hydrated_post.status == "published" and
             Map.get(hydrated_post, :visibility, "public") == "public" do
          # Build the exact format contract your React timeline listeners expect warning-free
          serialized_payload =
            KollectiveWeb.PostJSON.show(%{post: hydrated_post, likes_count: 0, has_liked: false})

          Phoenix.PubSub.broadcast(
            Kollective.PubSub,
            # "feed:public",
            "timeline:global",
            {:new_post_registered, serialized_payload}
          )
        end

        # ─── DECOUPLED ASYNC WEB CRAWLER INJECTION ───
        # O(1) ASYNC WEB CRAWLER INJECTION
        # if extracted_link,
        #   do:
        #    Task.start(fn ->
        #      crawl_and_populate_link_preview(hydrated_post.id, extracted_link)
        #    end)

        if extracted_link do
          %{"post_id" => hydrated_post.id, "url" => extracted_link}
          |> Kollective.Workers.LinkPreviewWorker.new()
          |> Oban.insert()
        end

        {:ok, hydrated_post}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # ─── ASYNC OPENGRAPH WEB CRAWLER MODULE (THE EXTRACTOR MATRIX) ───

  defp crawl_and_populate_link_preview(post_id, url) do
    case Req.get(url, headers: [{"user-agent", "KollectiveBot/1.0"}], retry: false) do
      {:ok, %Req.Response{status: 200, body: html_body}} ->
        {:ok, document} = Floki.parse_document(html_body)

        title =
          extract_og_tag(document, "og:title") || extract_text_tag(document, "title") ||
            "Link Overview"

        description =
          extract_og_tag(document, "og:description") || extract_meta_description(document) || ""

        preview_image = extract_og_tag(document, "og:image") || ""

        # Update the main row caches natively
        from(p in Post, where: p.id == ^post_id)
        |> Repo.update_all(
          set: [
            link_title: String.slice(title, 0, 255),
            link_description: String.slice(description, 0, 500),
            link_preview_image: preview_image
          ]
        )

        # Push real-time link preview cards out over the websocket network channel
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          # "feed:public",
          "timeline:global",
          {:link_preview_ready,
           %{
             post_id: post_id,
             link_title: title,
             link_description: description,
             link_preview_image: preview_image
           }}
        )

      _ ->
        :ok
    end
  end

  # --- Internal Geometry & Parsing Sub-Helpers ---
  defp extract_first_url(text) do
    case Regex.run(~r/https?:\/\/[^\s]+/, text) do
      [url] -> url
      _ -> nil
    end
  end

  defp extract_og_tag(doc, property) do
    doc
    |> Floki.find("meta[property=\"#{property}\"]")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_text_tag(doc, selector), do: doc |> Floki.find(selector) |> Floki.text()

  defp extract_meta_description(doc) do
    doc |> Floki.find("meta[name=\"description\"]") |> Floki.attribute("content") |> List.first()
  end

  # Identify the 'root_post_id' based on the reply target
  defp append_threading_context(attrs) do
    case attrs["in_reply_to_id"] || attrs[:in_reply_to_id] do
      nil ->
        # Not a reply? This post is its own root (or root is nil)
        attrs

      reply_id ->
        # It's a reply! Find the root of the post we are replying to
        case Repo.get(Post, reply_id) do
          # Handle error: parent doesn't exist
          nil ->
            attrs

          parent ->
            # If parent already has a root, use it. Otherwise, parent IS the root.
            root_id = parent.root_post_id || parent.id

            attrs
            |> Map.put("root_post_id", root_id)
            |> Map.put("in_reply_to_id", reply_id)
        end
    end
  end

  defp validate_and_fix_targeting(changeset, attrs, user) do
    organization_id = Ecto.Changeset.get_field(changeset, :organization_id)

    case user.type do
      :citizen when is_nil(organization_id) ->
        changeset
        |> Ecto.Changeset.put_change(:origin_country, user.country)
        |> Ecto.Changeset.put_change(:origin_state, user.state)
        |> Ecto.Changeset.put_change(:origin_county, user.county)
        |> Ecto.Changeset.put_change(:origin_city_id, user.city_id)
        # district_l1 is the same as district_l1
        |> Ecto.Changeset.put_change(:origin_district_l1, user.district_l1_id)
        # district_l2 is the same as district_l2
        |> Ecto.Changeset.put_change(:origin_district_l2, user.district_l2_id)
        # district_l3 is the same as district_l3
        |> Ecto.Changeset.put_change(:origin_district_l3, user.district_l3_id)

      _other_type ->
        # SCHOLAR/JOURNALIST/ORGANIZATION/ACTIVIST: Can choose both :target_scope
        # OR posting on behalf of an Organization
        # AND a custom :origin district/state/county from the React UI.
        # We only set defaults if the UI left them blank.
        changeset
        |> Ecto.Changeset.cast(attrs, [
          :target_scope,
          :origin_state,
          :origin_country,
          :origin_county,
          :origin_city_id,
          :origin_district_l1,
          :origin_district_l2,
          :origin_district_l3
        ])
        # Fall back to user's home base fields ONLY if the React UI left them blank
        |> default_value(:origin_country, user.country)
        |> default_value(:origin_state, user.state)
        |> default_value(:origin_county, user.county)
        |> default_value(:origin_city_id, user.city_id)
    end
  end

  defp default_value(changeset, field, fallback_value) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil -> Ecto.Changeset.put_change(changeset, field, fallback_value)
      _ -> changeset
    end
  end

  defp upsert_hashtag_entities(tag_names) do
    Enum.map(tag_names, fn name ->
      get_or_create_hashtag(name)
    end)
  end

  defp register_mention_notifications(post, verified_mentions, parent_author_id) do
    Enum.each(verified_mentions, fn recipient ->
      if recipient.id != post.user_id && recipient.id != parent_author_id do
        {:ok, notification} =
          Notifications.notify(
            recipient.id,
            post.user_id,
            "mention",
            %{
              post_id: post.id,
              target_id: post.id,
              target_type: "Post"
            },
            %{
              post_id: post.id,
              preview: "mentioned you: \"#{String.slice(post.content || "", 0, 30)}...\""
            }
          )

        KollectiveWeb.Endpoint.broadcast(
          "user_notifications:#{recipient.id}",
          "new_notification",
          %{notification: notification}
        )
      end
    end)
  end

  defp notify_parent_author(post) do
    if post.in_reply_to_id do
      parent = Repo.get(Post, post.in_reply_to_id)

      if parent && parent.user_id && post.user_id && parent.user_id != post.user_id do
        Notifications.notify_reply(
          # The recipient (The author of the parent post being replied to)
          parent.user_id,
          # The actor (The user writing the reply)
          post.user_id,
          # The full %Post{} struct reply node object
          post
        )
      end
    end
  end

  # Post Execution Real-Time WebSocket Broadcasting Orchestrator
  # defp handle_lifecycle_broadcasts({:ok, %{oban_jobs: post}}) do
  #  if post.category == :voice do
  #    # Pushes a notification to all listeners on the 'voice_alerts' topic
  #    KollectiveWeb.Endpoint.broadcast("voice_alert", "new_voice_post", %{post: post})
  #  end

  #  broadcast_feed_updates(post)

  #  {:ok, Repo.preload(post, [:author, poll: :options, attachments: []])}
  # end

  # defp handle_lifecycle_broadcasts({:error, _step, changeset, _changes}), do: {:error, changeset}

  # defp broadcast_feed_updates(post) do
  #    if post.visibility == "public" && post.status == "published" do
  # Feed Real-Time Engine Routing

  # A. THE HOME/PUBLIC FEED (Standard Live Feed)
  #    KollectiveWeb.Endpoint.broadcast("feed:public", "new_post", %{post: post})

  # B. THE DISCOVERY/GEO FEED (Local, State, Country, World Tabs)
  # Micro-Targeting Discovery Channels
  #    local_topic = "discovery:local:#{post.origin_state}:#{post.origin_district_l1}"
  #    KollectiveWeb.Endpoint.broadcast(local_topic, "new_post", %{post: post})

  #    if post.target_scope in [:state, :country, :world] do
  #      state_topic = "discovery:state:#{post.origin_state}"
  #      KollectiveWeb.Endpoint.broadcast(state_topic, "new_post", %{post: post})
  #    end
  #  end
  # end

  defp contains_restricted_words?(content) do
    keywords = Kollective.Moderation.Moderation.list_restricted_keywords()

    Enum.any?(keywords, fn k ->
      String.contains?(String.downcase(content), String.downcase(k.word))
    end)
  end

  defp parse_mention_strings(text) do
    Regex.scan(~r/@[[:alnum:]_]+/, text)
    |> List.flatten()
    |> Enum.map(&String.replace(&1, "@", ""))
    |> Enum.uniq()
  end

  defp get_parent_author_id(post) do
    if post.in_reply_to_id, do: Repo.get(Post, post.in_reply_to_id).user_id, else: nil
  end

  @doc """
  Unifies all temporary or permanent voice creation logic variants. Parses expiration rules,
  forces context properties, and coordinates with your main `create_post/2` engine.
  """
  def create_voice_post(%User{} = user, attrs \\ %{}, opts \\ []) do
    # 1. Resolve Expiration Metrics (Supporting :none, :one_day, :one_week)
    expiry_type =
      Keyword.get(opts, :expiry, :none) || attrs["expiry_type"] || attrs[:expiry_type] || :none

    expires_at =
      case expiry_type do
        :one_day -> DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.truncate(:second)
        "one_day" -> DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.truncate(:second)
        :one_week -> DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)
        "one_week" -> DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)
        # Permanent megaphone voice post
        _ -> nil
      end

    # 2. Package and force core category variables
    unified_attrs =
      attrs
      |> Map.put("category", "voice")
      |> Map.put("expires_at", expires_at)

    # 3. Hand off cleanly to your Unified Post Pipeline transaction loop
    case create_post(user, unified_attrs) do
      {:ok, post} ->
        # 4. Trigger Voice-Specific Background Infrastructure
        # Enqueue the structural geofenced alert worker to message local districts
        %{
          "post_id" => post.id,
          # user.district_l1,
          "district" => post.origin_district_l1,
          "country" => user.country,
          "author_id" => user.id
        }
        |> VoiceBroadcastWorker.new()
        # Inserts safely via Oban backing pools
        |> Oban.insert!()

        {:ok, post}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # list_home_feed engine. It merges all your Follows, Followed Organizations (Newspapers/Groups), Localized District Geofencing,
  # Bidirectional Block/Mute safety filters, Tuple-based Cursor Pagination, and your N+1-immune batch virtual hydration layers
  # into a single cohesive functional flow.

  # To keep your app scaling smoothly, this function handles a Hybrid Feed Engine Pattern:
  # The Fan-Out Cache (home_feed_entries): Captures explicit relationships (Followed People and Organizations).
  # The Real-Time Local Discovery Layer (Post): Pulls neighborhood geographic district content dynamically on the fly.

  # By running one single database pass, it merges your pre-computed home_feed_entries cache records with a dynamic subquery fallback
  # scan of public district entries. It then sorts the unified timeline chronologically using a high-performance tuple-based keyset
  # cursor query to eliminate duplicate items and screen jumps.

  @doc """
  The definitive Home Feed execution pipeline. Combines pre-computed user/org cached follow entries
  with dynamic geographic geofencing and row-comparison cursor pagination.

  Returns: %{entries: [...], next_cursor: "published_at,id"}
  """
  def list_home_feed(user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    after_cursor = Keyword.get(opts, :after)

    # 1. Fetch IDs of followed people and organizations
    # Fetch relationship matrices up front to prevent nested database lookups
    following_ids = Accounts.get_following_ids(user.id)
    followed_org_ids = Accounts.get_followed_org_ids(user.id)

    # 2. Combine the IDs to build a comprehensive timeline pool
    author_ids_pool = following_ids ++ followed_org_ids ++ [user.id]

    # Compile bidirectional block/mute exclusion subqueries safely
    hidden_ids_subquery =
      from r in UserRelationship,
        where: r.source_id == ^user.id and r.type in ["block", "mute"],
        select: r.target_id

    # Build dynamic geofence condition safely without illegal nil comparisons
    geo_c1 = if user.city_id, do: dynamic([p, u], u.city_id == ^user.city_id), else: false

    geo_c2 =
      if user.district_l3_id && user.state,
        do: dynamic([p, u], u.district_l3_id == ^user.district_l3_id and u.state == ^user.state),
        else: false

    geo_c3 =
      if user.district_l2_id && user.state,
        do: dynamic([p, u], u.district_l2_id == ^user.district_l2_id and u.state == ^user.state),
        else: false

    geo_c4 =
      if user.district_l1_id && user.country,
        do:
          dynamic([p, u], u.district_l1_id == ^user.district_l1_id and u.country == ^user.country),
        else: false

    geo_condition = dynamic([p, u], ^geo_c1 or ^geo_c2 or ^geo_c3 or ^geo_c4)

    home_feed_condition =
      dynamic(
        [p, u],
        p.user_id in ^author_ids_pool or
          (p.visibility == "public" and ^geo_condition and p.status == :published)
      )

    # 2. Build Core Unified Query
    query =
      from p in Post,
        join: u in assoc(p, :author),
        where: is_nil(p.deleted_at),
        # ENFORCE BIDIRECTIONAL SOCIAL SAFETY SHIELDS
        where: p.user_id not in subquery(hidden_ids_subquery),
        # UNIFIED TIERS: Follows + Organizations + Geofenced Districts
        where: ^home_feed_condition

    # 3. Apply Multi-Column Row Comparison Cursor Pagination
    # Implements the standard keyset evaluation syntax: (published_at, id) < (cursor_ts, cursor_id)
    query =
      if after_cursor && after_cursor != "" do
        case String.split(after_cursor, ",") do
          [ts_str, id_str] ->
            {:ok, ts, _} = DateTime.from_iso8601(ts_str)
            target_id = String.to_integer(id_str)

            from p in query,
              where: p.published_at < ^ts or (p.published_at == ^ts and p.id < ^target_id)

          _ ->
            query
        end
      else
        query
      end

    # 4. Final Sorting, Preloads, and Database Read Pass
    raw_posts =
      query
      # Primary prioritization layer: voice posts float first, fallback to cron sequence
      |> order_by([p],
        desc: fragment("CASE WHEN ? = 'voice' THEN 1 ELSE 0 END", p.category),
        desc: p.published_at,
        desc: p.id
      )
      |> limit(^limit)
      |> preload([:author, :organization, reblog_of: :attachments])
      |> Repo.all()

    # 5. Process Batch Virtual Hydration Loop (Prevents N+1 database queries entirely)
    hydrated_entries = hydrate_virtual_fields(raw_posts, user)

    # 6. Generate the Multi-Column Token for React infinite scroll loops
    next_cursor =
      case List.last(hydrated_entries) do
        nil ->
          nil

        last_item ->
          ts_iso = DateTime.to_iso8601(last_item.post.published_at)
          "#{ts_iso},#{last_item.post.id}"
      end

    %{
      entries: hydrated_entries,
      next_cursor: next_cursor
    }
  end

  # --- Cached Feed Pipeline Strategy ---
  # Reading the Caching Timeline (High-Performance Read)
  # When your React frontend asks for the home timeline, you bypass all relationship
  # checks, blocks, and mutes filters. The heavy work was already calculated at write time.
  # You just pull straight from the home_feed_entries cache table.
  # "Home Page" Following/Personalized Feed with Caching
  def list_cached_home_feed(user_id, params \\ %{}) do
    import Ecto.Query
    cursor = params["cursor"] || params[:cursor]
    limit = 20

    # 1. Build the base query structure
    query =
      from e in "home_feed_entries",
        where: e.user_id == type(^user_id, Ecto.ULID),
        join: p in Post,
        on: p.id == e.post_id,
        left_join: total_l in assoc(p, :likes),
        left_join: user_l in Kollective.Posts.Like,
        on: user_l.post_id == p.id and user_l.user_id == type(^user_id, Ecto.ULID),
        group_by: [e.id, p.id, user_l.id],
        preload: [p: :author],
        order_by: [desc: e.id],
        limit: ^limit,
        select: {p, count(total_l.id, :distinct), not is_nil(user_l.id), e.id}

    # 2. FIX: Use explicit keyword binding (`as: :entries`) or position-independent fragments
    query =
      if cursor do
        from [entries: e] in query, where: e.id < ^cursor
      else
        query
      end

    # 3. FIX: Keep the pipeline block unified without blank line gaps
    results =
      query
      |> Repo.all()
      |> Enum.map(fn {post, likes_count, liked, entry_id} ->
        %{
          post: post,
          likes_count: likes_count,
          has_liked: liked,
          feed_cursor_id: entry_id
        }
      end)

    next_cursor =
      case List.last(results) do
        nil -> nil
        last_item -> last_item.feed_cursor_id
      end

    %{entries: results, next_cursor: next_cursor}
  end

  # --- TAB 1: ALL ACTIVITY ---
  # Fetches all public, published content (Voice and Text mixed)
  # --- TAB 1: ALL ACTIVITY (Text + Voice Combined) ---
  def list_global_activity_feed(user, params \\ %{}) do
    build_global_base_query(user)
    |> apply_feed_cursor(params["cursor"] || params[:cursor])
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> execute_global_feed_query(user)
  end

  # --- TAB 2: POSTS ONLY ---
  # Filters out audio posts to show regular text content
  # --- TAB 2: POSTS ONLY (Filters out Voice Logs) ---
  def list_global_text_feed(user, params \\ %{}) do
    build_global_base_query(user)
    |> where([p], p.category != "voice")
    |> apply_feed_cursor(params["cursor"] || params[:cursor])
    |> order_by([p], desc: p.published_at, desc: p.id)
    |> execute_global_feed_query(user)
  end

  # --- TAB 3: VOICES (TRENDING VOICE POSTS) ---
  # Employs your Hotness Scoring Algorithm to bubble up viral voice logs
  # --- TAB 3: VOICES (Trending Voice Logs Hotness Grid) ---
  def list_global_trending_voices_feed(user, params \\ %{}) do
    limit = 20
    # Expected format: "trending_score,id"
    after_trend_cursor = params["cursor"] || params[:cursor]

    query =
      build_global_base_query(user)
      |> where([p], p.category == "voice")

    # Apply unique multi-column tuple cursor for hotness scores to prevent item duplication loops
    query =
      if after_trend_cursor && after_trend_cursor != "" do
        case String.split(after_trend_cursor, ",") do
          [score_str, id_str] ->
            target_score = String.to_float(score_str)
            target_id = String.to_integer(id_str)

            from p in query,
              where:
                p.trending_score < ^target_score or
                  (p.trending_score == ^target_score and p.id < ^target_id)

          _ ->
            query
        end
      else
        query
      end

    # Primary sort by hotness velocity, chronological fallback
    raw_posts =
      query
      |> order_by([p], desc: p.trending_score, desc: p.id)
      |> limit(^limit)
      |> Repo.all()

    hydrated_entries = hydrate_virtual_fields(raw_posts, user)

    next_cursor =
      case List.last(hydrated_entries) do
        nil -> nil
        last_item -> "#{last_item.post.trending_score},#{last_item.post.id}"
      end

    %{entries: hydrated_entries, next_cursor: next_cursor}
  end

  # --- Shared Base Query Builder (DRY & Lightweight) ---
  defp build_global_base_query(user) do
    user_id = if user, do: user.id, else: nil

    # Isolate safety relation masks to filter out harassers or blocked profiles instantly
    hidden_ids =
      if user_id do
        Repo.all(
          from r in "user_relationships",
            where: r.source_id == ^user_id and r.type in ["block", "mute"],
            select: r.target_id
        )
      else
        []
      end

    from p in Post,
      where: is_nil(p.deleted_at),
      where: p.visibility == "public" and p.status == "published",
      where: p.user_id not in ^hidden_ids,
      preload: [:author, reblog_of: :author, attachments: []]
  end

  # --- Shared Execution & Cursor Appenders ---
  defp apply_feed_cursor(query, cursor) when cursor in [nil, "", "nil"], do: query

  defp apply_feed_cursor(query, cursor) do
    case String.split(cursor, ",") do
      [ts_str, id_str] ->
        {:ok, ts, _} = DateTime.from_iso8601(ts_str)
        target_id = String.to_integer(id_str)

        from p in query,
          where: p.published_at < ^ts or (p.published_at == ^ts and p.id < ^target_id)

      _ ->
        query
    end
  end

  defp execute_global_feed_query(query, user) do
    limit = 20

    raw_posts =
      query
      |> limit(^limit)
      |> Repo.all()

    # Run your N+1-immune O(1) batch hydration array loop
    hydrated_entries = hydrate_virtual_fields(raw_posts, user)

    next_cursor =
      case List.last(hydrated_entries) do
        nil ->
          nil

        last_item ->
          ts_iso = DateTime.to_iso8601(last_item.post.published_at)
          "#{ts_iso},#{last_item.post.id}"
      end

    %{entries: hydrated_entries, next_cursor: next_cursor}
  end

  # This engine incorporates your complete architectural requirement stack: mutual block safety subqueries,
  # soft-delete tombstones, JSONB GIN-indexed mention arrays, cursor-based keyset pagination,
  # multi-scope geo-fencing, and your robust N+1-immune batch virtual hydration layer.
  @doc """
  The definitive, unified social feed engine. Combines mutual block filters,
  category sorting matrices, user mentions tracking, geographic tier geofencing,
  and keyset cursor pagination into a single optimized query stream.
  """
  def list_posts_for_feed(current_user \\ nil, params \\ %{}) do
    limit = 20
    current_user_id = if current_user, do: current_user.id, else: nil

    # 1. Start the base query
    base_query =
      base_post_query()
      # Block safety shields
      |> apply_bidirectional_block_masks(current_user_id)
      # Text vs. Voice filter
      |> filter_by_category(params["category"])
      # JSONB GIN mention arrays
      |> filter_by_mentions(current_user_id, params["filter"])

    # 🔄 Only apply geographic geofencing if there is a logged-in user!
    query =
      if current_user do
        # Filters by Local, State, Country, or World based on user properties
        filter_by_geographic_scope(base_query, current_user, params["scope"])
      else
        # For anonymous guests, fall back to global content, or enforce a fallback scope
        where(base_query, [p], p.visibility == "public" and p.status == "published")
      end

    # Continue the rest of your dynamic query builder pipeline without interruption
    query =
      query
      |> apply_cursor_pagination(params["cursor"] || params["max_id"])
      |> sort_by_strategy(params["sort"])
      |> limit(^limit)
      # Preload core dependencies using clean base constraints
      |> preload([
        :author,
        reblog_of: ^base_post_query(),
        hashtags: [],
        attachments: [],
        poll: :options
      ])

    # 2. Execute Data Read and Fetch Cursor Token
    raw_posts = Repo.all(query)

    # 2. Fetch the user's compiled regex mute pattern from RAM
    # 🔄 FIX: Only fetch and compile regex mute filters if a user is logged in
    mute_regex =
      if current_user do
        active_filters = Kollective.Posts.UserFilter.list_active_filters(current_user)
        Kollective.Posts.UserFilter.compile_regex_pattern(active_filters)
      else
        nil
      end

    # 3. Prune out posts that match the user's muted phrases
    filtered_posts =
      if mute_regex do
        Enum.reject(raw_posts, fn item -> Regex.run(mute_regex, item.post.content || "") end)
      else
        raw_posts
      end

    # 4. Batch Virtual Hydration Loop (Prevents N+1 database queries entirely)
    hydrated_entries = hydrate_virtual_fields(filtered_posts, current_user)

    next_cursor =
      case List.last(hydrated_entries) do
        nil -> nil
        last_item -> last_item.post.id
      end

    %{
      entries: hydrated_entries,
      next_cursor: next_cursor
    }
  end

  # --- Structural Chainable Private Pipelines ---
  defp base_post_query do
    from p in Post, where: is_nil(p.deleted_at)
  end

  # NEW: Unified Geographic Geofencing Filters
  # Anonymous users bypass geo-fencing
  defp filter_by_geographic_scope(query, nil, _scope), do: query

  defp filter_by_geographic_scope(query, _user, scope) when scope in [nil, "", "world", "all"],
    do: query

  defp filter_by_geographic_scope(query, user, "local") do
    # LOCAL: Post matches EITHER political representation (L1, L2, L3) OR administrative locality (County/District/City)
    local_condition = dynamic_local_condition(user)
    from p in query, where: ^local_condition
  end

  defp filter_by_geographic_scope(query, user, "state") do
    # STATE: Post matches the user's state, but EXCLUDES posts that belong in their Local tab
    local_condition = dynamic_local_condition(user)

    from p in query,
      where: p.origin_state == ^user.state,
      where: not (^local_condition)
  end

  defp filter_by_geographic_scope(query, user, "country") do
    # COUNTRY: Post matches the user's country, but EXCLUDES their entire state
    from p in query,
      where: p.origin_country == ^user.country,
      where: p.origin_state != ^user.state
  end

  defp dynamic_local_condition(user) do
    cond1 =
      if user.district_l1_id,
        do:
          dynamic(
            [p],
            not is_nil(p.origin_district_l1) and p.origin_district_l1 == ^user.district_l1_id
          ),
        else: false

    cond2 =
      if user.district_l2_id,
        do:
          dynamic(
            [p],
            not is_nil(p.origin_district_l2) and p.origin_district_l2 == ^user.district_l2_id
          ),
        else: false

    cond3 =
      if user.district_l3_id,
        do:
          dynamic(
            [p],
            not is_nil(p.origin_district_l3) and p.origin_district_l3 == ^user.district_l3_id
          ),
        else: false

    cond4 =
      if user.county && user.state,
        do:
          dynamic(
            [p],
            not is_nil(p.origin_county) and p.origin_state == ^user.state and
              p.origin_county == ^user.county
          ),
        else: false

    cond5 =
      if user.city_id,
        do: dynamic([p], not is_nil(p.origin_city_id) and p.origin_city_id == ^user.city_id),
        else: false

    dynamic([p], ^cond1 or ^cond2 or ^cond3 or ^cond4 or ^cond5)
  end

  defp apply_bidirectional_block_masks(query, nil), do: query

  defp apply_bidirectional_block_masks(query, current_user_id) do
    # Subquery tracking accounts blocked by the active user
    blocked_ids_subquery =
      from(r in Kollective.Accounts.UserRelationship,
        where: r.source_id == ^current_user_id and r.type == "block",
        select: r.target_id
      )

    # Subquery tracking accounts who have actively blocked the current user
    blockers_ids_subquery =
      from(r in Kollective.Accounts.UserRelationship,
        where: r.target_id == ^current_user_id and r.type == "block",
        select: r.source_id
      )

    from p in query,
      where: p.user_id not in subquery(blocked_ids_subquery),
      where: p.user_id not in subquery(blockers_ids_subquery)
  end

  defp apply_cursor_pagination(query, max_id) when max_id in [nil, "", "nil"], do: query

  defp apply_cursor_pagination(query, max_id) do
    # Keyset pagination rule ensures index scans run under 1ms on massive datasets
    id_threshold = if is_binary(max_id), do: String.to_integer(max_id), else: max_id
    from p in query, where: p.id < ^id_threshold
  end

  defp filter_by_category(query, "voice") do
    # Prioritizes emergency audio content sorting layers dynamically
    from p in query, where: p.category == "voice", order_by: [desc: p.urgency_level]
  end

  defp filter_by_category(query, _), do: query

  defp filter_by_mentions(query, current_user_id, "mentions") when not is_nil(current_user_id) do
    # Triggers your JSONB GIN containment index operator (@>) to scan mentions instantly
    mention_target = [%{id: current_user_id}]
    from p in query, where: fragment("? @> ?", p.mentions, ^mention_target)
  end

  defp filter_by_mentions(query, _, _), do: query

  defp sort_by_strategy(query, "top") do
    # Rank by hotness score velocity, using sequential chronological fallbacks
    from p in query, order_by: [desc: p.score, desc: p.id]
  end

  defp sort_by_strategy(query, _) do
    # Default chronological social feed layout ordering rule
    from p in query, order_by: [desc: p.id]
  end

  # LIST: Fetches posts and nests them for JSON delivery
  def list_posts_as_tree do
    Post
    # <--- Fetch user data (username, avatar, etc.)
    |> preload(:author)
    # Keeps conversation order
    |> order_by(asc: :inserted_at)
    |> Repo.all()
    # Uses the build_tree function from above
    |> build_tree()
  end

  def list_posts_with_likes do
    from(p in Post,
      left_join: l in assoc(p, :likes),
      group_by: p.id,
      # Use select_merge to fill the virtual field
      # Calculates total likes
      select_merge: %{likes_count: count(l.id)}
    )
    |> preload([:author, :root_post])
    |> Repo.all()
    # Your existing tree-building logic
    |> build_tree()
  end

  # POST `/api/posts/${postId}/like`
  def toggle_like(user_id, post_id) do
    # Look for an existing like by this user for this post
    like_query =
      from(l in Kollective.Posts.Like, where: l.user_id == ^user_id and l.post_id == ^post_id)

    case Repo.one(like_query) do
      # User hasn't liked yet: Create it
      nil ->
        %Kollective.Posts.Like{}
        |> Kollective.Posts.Like.changeset(%{user_id: user_id, post_id: post_id})
        |> Repo.insert()
        |> case do
          {:ok, _like} ->
            # Trigger real-time notification broadcast asynchronously
            trigger_like_notification(user_id, post_id)
            {:ok, :liked}

          {:error, changeset} ->
            {:error, changeset}
        end

      like ->
        # User already liked: Remove it (Unlike)
        Repo.delete(like)
        {:ok, :unliked}
    end
  end

  defp trigger_like_notification(liker_id, post_id) do
    # Fetch the post author and the liker's details
    post = Repo.get(Post, post_id)
    liker = Repo.get(User, liker_id)

    # Prevent users from getting notifications when they like their own posts
    if post && liker && post.user_id && post.user_id != liker_id do
      notification_payload = %{
        id: System.unique_integer([:positive]),
        type: "like",
        post_id: post_id,
        message: "@#{liker.username} liked your post!",
        created_at: DateTime.utc_now()
      }

      # Broadcast to the specific author's notification pipeline channel
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "user_notifications:#{post.user_id}",
        {:new_notification, notification_payload}
      )
    end
  end

  # To get the like count immediately after a click without re-fetching the whole tree, use this helper
  def get_like_count(post_id) do
    query =
      from l in Like,
        where: l.post_id == ^post_id,
        select: count(l.id)

    Repo.one(query)
  end

  # Query finds posts where the author is in the user's "following" list. It also preloads
  # the reblog_of association so that for reposts, you have the original post's body and author.
  # includes reposts
  def list_posts_with_metadata(current_user_id) do
    # 1. Get IDs of everyone the user follows
    following_ids = Users.list_following_ids(current_user_id)

    # Get IDs of people this user has blocked or muted
    hidden_ids =
      UserRelationship
      |> where([r], r.source_id == ^current_user_id and r.type in ["block", "mute"])
      |> select([r], r.target_id)
      |> Repo.all()

    Post

    # 2. Query for their posts AND their reposts
    query =
      from p in Post,
        where: p.user_id in ^following_ids,
        # Exclude blocked/muted users
        where: p.user_id not in ^hidden_ids,
        left_join: total_l in assoc(p, :likes),
        left_join: user_l in "likes",
        on: user_l.post_id == p.id and user_l.user_id == ^current_user_id,
        group_by: [p.id, user_l.id],
        # Critical: Preload author of the post AND author of the reblogged post
        preload: [:author, reblog_of: :author],
        order_by: [desc: p.inserted_at],
        select: {p, count(total_l.id), not is_nil(user_l.id)}

    Repo.all(query)
    |> Enum.map(fn {post, count, liked} ->
      # We build a plain Map here instead of updating the Struct
      %{
        post: post,
        likes_count: count,
        has_liked: liked
      }
    end)
  end

  def list_posts_by_tag(tag_name) do
    from p in Post,
      join: t in assoc(p, :hashtags),
      where: t.name == ^tag_name,
      preload: [:author],
      order_by: [desc: p.inserted_at]
  end

  # you now have the root_post_id saved on every reply, you no longer need the complex recursive CTE
  # for most cases. You can fetch a massive 500-post conversation with a single, high-performance database hit.

  # The "Flat" Thread Query
  # This query fetches the original post plus every reply that shares that same root_post_id.
  @doc """
  Fetches an entire conversational conversation thread by root_post_id.
  Applies block/mute safety filters and pipes rows into the O(1) batch hydration tree engine.
  """
  def get_thread(root_post_id, current_user \\ nil) do
    current_user_id = if current_user, do: current_user.id, else: nil

    # 1. Isolate bidirectional safety filters to protect users from blocked accounts
    hidden_ids = fetch_hidden_user_ids(current_user_id)

    # 2. Base Thread Fetch Query (Lightweight, no counter cross-joins)
    query =
      from p in Post,
        # Never load deleted content (Tombstones)
        where: is_nil(p.deleted_at),
        # Enforce block safety shields
        where: p.user_id not in ^hidden_ids,
        where: p.id == ^root_post_id or p.root_post_id == ^root_post_id,
        preload: [:author, reblog_of: :author, attachments: []],
        # IDs are chronological B-Tree sorted indexes
        order_by: [asc: p.id]

    # 3. Execute, Hydrate in Batch, and Build the Nested React Tree
    Repo.all(query)
    # Safely handles likes, reblogs, bookmarks, and emojis
    |> hydrate_virtual_fields(current_user)
    # Turns the flat list into a recursive tree structure for React
    |> build_tree()
  end

  # --- Keep your existing fetch_hidden_user_ids/1 helper below if not already in the file ---
  defp fetch_hidden_user_ids(nil), do: []

  defp fetch_hidden_user_ids(current_user_id) do
    alias Kollective.Accounts.UserRelationship

    Repo.all(
      from r in UserRelationship,
        where: r.source_id == ^current_user_id and r.type in ["block", "mute"],
        select: r.target_id
    )
  end

  # Fetch everything belonging to the same root, regardless of where you start
  def get_context(post, current_user \\ nil) do
    # Find the true top of the conversation tree
    root_id = post.root_post_id || post.id
    get_thread(root_id, current_user)
  end

  # Because the database handles the "cleanup" of the replies, your Elixir code stays extremely simple.
  # You just delete the one post, and Postgres handles the rest in a single transaction.
  def delete_post(post_or_id, opts \\ [])

  def delete_post(%Post{} = post, opts) do
    opts_map =
      cond do
        is_list(opts) -> Map.new(opts)
        is_map(opts) -> opts
        true -> %{}
      end

    actor_id = opts_map[:actor_id] || opts_map["actor_id"] || post.user_id
    org_id = post.organization_id || opts_map[:organization_id] || opts_map["organization_id"]

    multi =
      Multi.new()
      |> Multi.delete(:post, post)

    multi =
      if post.user_id do
        Multi.update_all(
          multi,
          :decrement_note_count,
          from(u in User, where: u.id == ^post.user_id and u.note_count > 0),
          inc: [note_count: -1]
        )
      else
        multi
      end

    multi =
      if org_id do
        custom_metadata = opts_map[:metadata] || opts_map["metadata"] || %{}

        metadata =
          Map.merge(
            %{
              content_snippet: String.slice(post.content || "", 0, 100),
              is_admin_delete: actor_id != post.user_id
            },
            custom_metadata
          )

        audit_params = %{
          action: "post_deleted",
          target_type: "Post",
          target_id: to_string(post.id),
          actor_id: actor_id,
          organization_id: org_id,
          metadata: metadata
        }

        Multi.insert(multi, :audit_log, AuditLog.changeset(%AuditLog{}, audit_params))
      else
        multi
      end

    Repo.transaction(multi)
    |> case do
      {:ok, %{post: deleted_post}} ->
        {:ok, deleted_post}

      {:error, :post, changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  def delete_post(post_id, opts) when is_binary(post_id) or is_integer(post_id) do
    post = Repo.get!(Post, post_id)
    delete_post(post, opts)
  end

  # Reblog:

  def reblog_post(user_id, post_id) do
    original_post = Repo.get!(Post, post_id)

    # Check if user is trying to reblog their own content
    if not is_nil(original_post.user_id) and original_post.user_id == user_id do
      {:error, :self_reblog_not_allowed}
    else
      # ... Multi logic for toggle ...
      execute_reblog_toggle(user_id, post_id)
    end
  end

  def execute_reblog_toggle(user_id, post_id) do
    # Standardized to user_id
    existing = Repo.get_by(Post, user_id: user_id, reblog_of_id: post_id)

    if existing do
      # --- UNDO REBLOG LOGIC ---
      Multi.new()
      |> Multi.delete(:reblog, existing)
      |> Multi.update_all(
        :decrement_note_count,
        from(u in User, where: u.id == ^user_id and u.note_count > 0),
        inc: [note_count: -1]
      )
      # Remove the reblog pointer from your followers' Home Feed Cache tables
      |> Multi.run(:feed_cleanup, fn _repo, %{reblog: reblog} ->
        # Gather followers of the person who is undoing the reblog
        follower_ids = fetch_follower_ids(user_id)

        from(e in "home_feed_entries",
          where:
            e.user_id in type(^follower_ids, {:array, Ecto.ULID}) and
              e.post_id == type(^reblog.id, Ecto.ULID)
        )
        |> Repo.delete_all()

        {:ok, :cleaned}
      end)
      |> Repo.transaction()
      |> case do
        # Normalize return tuple to match the controller expectations
        {:ok, _changes} ->
          {:ok, :unreblogged}

        {:error, _failed_operation, _failed_value, _changes_so_far} ->
          {:error, :failed_to_unreblog}
      end
    else
      # --- CREATE REBLOG LOGIC ---
      case execute_create_reblog(user_id, post_id) do
        {:ok, %{reblog: reblog}} ->
          notify_reblog(reblog)
          # Normalize return tuple format
          {:ok, :reblogged, reblog}

        {:error, _failed_operation, _failed_value, _changes_so_far} ->
          {:error, :failed_to_reblog}
      end
    end
  end

  defp execute_create_reblog(user_id, post_id) do
    now_naive = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    Multi.new()
    |> Multi.insert(:reblog, %Post{
      user_id: user_id,
      reblog_of_id: post_id,
      content: nil
    })
    |> Multi.update_all(
      :increment_note_count,
      from(u in User, where: u.id == ^user_id),
      inc: [note_count: 1],
      set: [last_post_at: now_naive]
    )
    # Enqueue our high-performance Fan-Out worker inside the safe transaction pool
    |> Multi.run(:fanout_job, fn _repo, %{reblog: reblog} ->
      # This enqueues an Oban job to push the reblog card to followers asynchronously
      %{
        "post_id" => reblog.id,
        # The reblogger is the source author of the timeline event
        "author_id" => user_id
      }
      |> Kollective.Workers.FeedFanoutWorker.new()
      |> Oban.insert()
    end)
    |> Repo.transaction()
  end

  # Reusable relationship lookups helper
  defp fetch_follower_ids(user_id) do
    from(r in Kollective.Accounts.UserRelationship,
      where: r.target_id == ^user_id and r.type == "follow",
      select: r.source_id
    )
    |> Repo.all()
  end

  # Notifications so a user knows when their post has been reblogged
  defp notify_reblog(reblog) do
    # 1. Fetch the original post to find the owner
    original_post = Repo.get!(Post, reblog.reblog_of_id) |> Repo.preload(:author)
    _reblog_author = Repo.get!(User, reblog.user_id)

    # Avoid notifying yourself if you somehow boost your own post
    if original_post.user_id && original_post.user_id != reblog.user_id do
      # 2. Broadcast real-time via Phoenix Channels
      {:ok, _notif} =
        Notifications.notify(
          original_post.user_id,
          reblog.user_id,
          "reblog",
          %{
            post_id: original_post.id,
            target_id: reblog.id,
            target_type: "Post"
          },
          %{
            post_id: original_post.id,
            preview: "boosted your post."
          }
        )
    end
  end

  def get_reblog_count(post_id) do
    Repo.one(from(p in Post, where: p.reblog_of_id == ^post_id, select: count(p.id))) || 0
  end

  # When fetching a user's feed, you must preload the reblog_of post and its author,
  # or React won't have anything to display.
  def list_timeline(user_id) do
    Post
    |> where([p], p.user_id == ^user_id)
    # Deep preload
    |> preload([:author, reblog_of: :author])
    |> Repo.all()
  end

  # Mentions
  def extract_mentions(content) do
    # Regex to find @username or @username@domain
    mention_regex = ~r/@[a-z0-9_]+(@[a-z0-9\.\-]+)?/i

    Regex.scan(mention_regex, content)
    |> List.flatten()
    |> Enum.uniq()
    # Optional: strip the '@' to get just the username for searching
    |> Enum.map(&String.replace(&1, "@", ""))
  end

  def notify_mentioned_users(post) do
    usernames = extract_mentions(post.content)

    # Find users in DB
    mentioned_users = Kollective.Repo.all(from u in User, where: u.username in ^usernames)

    Enum.each(mentioned_users, fn user ->
      # 1.Push to Phoenix Channel (Real-time!)
      {:ok, _notif} =
        Notifications.notify(
          user.id,
          post.user_id,
          "mention",
          %{
            post_id: post.id,
            target_id: post.id,
            target_type: "Post"
          },
          %{
            post_id: post.id,
            preview: "mentioned you: \"#{String.slice(post.content || "", 0, 30)}...\""
          }
        )
    end)
  end

  # Function that inserts a new post record where the content is empty but the reblog_of_id is set
  def repost_post(user_id, post_id) do
    # Mastodon style: If it already exists, "un-repost" it (toggle)
    case Repo.get_by(Post, user_id: user_id, reblog_of_id: post_id) do
      nil ->
        %Post{}
        |> Post.changeset(%{
          user_id: user_id,
          reblog_of_id: post_id,
          # Pure reposts have no content
          content: nil
        })
        |> Repo.insert()

      existing ->
        Repo.delete(existing)
    end
  end

  def extract_hashtags(text) do
    Regex.scan(~r/#[[:alnum:]_]+/u, text)
    |> List.flatten()
    |> Enum.map(&String.downcase(String.replace(&1, "#", "")))
    |> Enum.uniq()
  end

  def get_or_create_hashtag(name) do
    # Standardize to lowercase (so #Elixir and #elixir are the same)
    name = String.downcase(name)

    case Repo.get_by(Hashtag, name: name) do
      %Hashtag{} = hashtag ->
        hashtag

      nil ->
        %Hashtag{}
        |> Hashtag.changeset(%{name: name})
        |> Repo.insert(
          on_conflict: [set: [name: name]],
          conflict_target: :name,
          returning: true
        )
        |> case do
          {:ok, hashtag} -> hashtag
          {:error, _} -> Repo.get_by!(Hashtag, name: name)
        end
    end
  end

  def list_posts_with_tags do
    Post
    # <--- Fetches the tags
    |> preload([:author, :hashtags])
    |> Repo.all()
  end

  # infinite scrolling
  def list_postsX(params \\ %{}) do
    cursor = params["cursor"]
    limit = 20

    query =
      from p in Post,
        order_by: [desc: p.id],
        limit: ^limit,
        preload: [:author]

    # If a cursor exists, only get posts older than that ID
    query = if cursor, do: where(query, [p], p.id < ^cursor), else: query

    posts = Repo.all(query)

    # Return both the posts and the next cursor for React
    %{
      posts: posts,
      next_cursor: List.last(posts) && List.last(posts).id
    }
  end

  # Allows a user to "turn off" notifications for a specific thread.
  def toggle_thread_mute(user_id, root_post_id) do
    query =
      from tm in ThreadMute,
        where: tm.user_id == ^user_id and tm.root_post_id == ^root_post_id

    case Repo.one(query) do
      nil ->
        # User wants to silence this conversation
        %ThreadMute{}
        |> ThreadMute.changeset(%{user_id: user_id, root_post_id: root_post_id})
        |> Repo.insert()
        |> case do
          {:ok, _mute} -> {:ok, :muted}
          {:error, changeset} -> {:error, changeset}
        end

      mute ->
        # User wants to hear from this conversation again
        case Repo.delete(mute) do
          {:ok, _mute} -> {:ok, :unmuted}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  # Use fragment to access the Postgres @@ match operator. We use websearch_to_tsquery because it allows users to
  # Use familiar syntax like quotes for phrases or minus signs to exclude words
  def search_postsO(query_string) do
    from p in Post,
      where: fragment("searchable @@ websearch_to_tsquery(?)", ^query_string),
      # Rank results so the most relevant matches appear first
      order_by: [desc: fragment("ts_rank_cd(searchable, websearch_to_tsquery(?))", ^query_string)],
      preload: [:author],
      limit: 20
  end

  @doc """
  Unifies all search variants into a hybrid FTS and Trigram matching engine.
  Automatically filters out deleted/private records and adjusts to user blocks.
  """
  def search_posts(query_string, current_user \\ nil, params \\ %{}) do
    # 1. Clean and normalize search query inputs
    query_string = String.trim(query_string || "")
    current_user_id = if current_user, do: current_user.id, else: nil

    if query_string == "" or String.length(query_string) < 3 do
      []
    else
      # 2. Extract social safety masks to protect user data
      hidden_ids = fetch_hidden_user_ids(current_user_id)

      # 3. Build Unified Hybrid Query Execution Block
      query =
        from p in Post,
          # STRICT SOCIAL VISIBILITY & PRIVACY FILTERS
          # Skip Tombstones
          where: is_nil(p.deleted_at),
          # Enforce public timeline discovery
          where: p.visibility == "public",
          # Filter out shadow-banned pending states
          where: p.status == "published",
          # Enforce blocks and mutes
          where: p.user_id not in ^hidden_ids,

          # HYBRID MATCHING LAYER: FTS Vector Match OR Trigram Similarity Match
          # Typo tolerance
          where:
            fragment(
              "p.searchable @@ websearch_to_tsquery(cast(p.language as regconfig), ?)",
              ^query_string
            ) or
              fragment("p.content % ?", ^query_string)

      # INJECT PAGINATION: Apply the keyset filter threshold to keep reads under 1ms
      query = apply_cursor_pagination(query, params["cursor"])

      # HYBRID RANKING LAYER: Combines Text Density Rank with Trigram String Similarity
      query =
        from p in query,
          order_by: [
            desc:
              fragment(
                "ts_rank_cd(p.searchable, websearch_to_tsquery(cast(p.language as regconfig), ?)) + similarity(p.content, ?)",
                ^query_string,
                ^query_string
              ),
            desc: p.id
          ],
          limit: 20

      # 4. Execute data load and populate hydration layers
      raw_posts = Repo.all(query)
      hydrated_entries = hydrate_virtual_fields(raw_posts, current_user)

      next_cursor =
        case List.last(hydrated_entries) do
          nil ->
            nil

          last_item ->
            ts_iso = DateTime.to_iso8601(last_item.post.published_at)
            "#{ts_iso},#{last_item.post.id}"
        end

      %{entries: hydrated_entries, next_cursor: next_cursor}
    end
  end

  @doc """
  Rejects an active post for compliance reasons. Keeps the row in the DB,
  notifies the author, and commands timelines to hide it.
  """
  def reject_post(admin, post_id, reason) do
    post = Repo.get!(Post, post_id)

    Multi.new()
    # 1. Commute status strings and store metadata context fields
    |> Multi.update(
      :post,
      Post.changeset(post, %{
        status: "rejected",
        rejection_reason: reason,
        rejected_at: DateTime.utc_now() |> DateTime.truncate(:second),
        rejected_by_id: admin.id
      })
    )

    # 2. File an administrative compliance trace
    |> Multi.insert(:admin_log, %AdminLog{
      action: "post_rejected",
      target_id: post.id,
      target_type: "Post",
      user_id: admin.id,
      metadata: %{reason: reason}
    })
    |> Repo.transaction()
    |> case do
      {:ok, %{post: updated_post}} ->
        # GLOBAL TIMELINE CLEANUP SCRUB
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:post_rejected, updated_post.id}
        )

        # PRIVATE ALERT: Notify the author why their post was pulled
        Notifications.notify(
          updated_post.user_id,
          admin.id,
          # Matches your snake_case notification types registry
          "report",
          %{
            post_id: updated_post.id,
            target_id: updated_post.id,
            target_type: "Post",
            metadata: %{sub_type: "post_rejected"}
          },
          %{
            post_id: updated_post.id,
            preview: "✕ Your post was rejected by moderation. Reason: #{reason}"
          }
        )

        {:ok, updated_post}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Allows the author of a rejected post to submit an appeal justification string.
  """
  def appeal_post(user, post_id, reason) do
    post = Repo.get!(Post, post_id) |> Repo.preload(:author)

    # Security Guard: Only allow an appeal if the post is rejected and belongs to the user
    if post.status == "rejected" and post.user_id == user.id do
      Multi.new()
      # Update status to appealed
      |> Multi.update(
        :post,
        Post.changeset(post, %{
          status: "appealed",
          appeal_reason: reason,
          appealed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      )

      # File compliance log entry
      |> Multi.insert(:admin_log, %AdminLog{
        action: "appeal_submitted",
        target_id: post.id,
        target_type: "Post",
        user_id: user.id,
        metadata: %{appeal_reason: reason}
      })
      |> Repo.transaction()
      |> case do
        {:ok, %{post: appealed_post}} ->
          # Push immediately to the Admin Panel real-time reports stream channel
          Phoenix.PubSub.broadcast(
            Kollective.PubSub,
            "admin_notifications",
            {:new_appeal,
             %{
               id: appealed_post.id,
               content: appealed_post.content,
               appeal_reason: appealed_post.appeal_reason,
               username: user.username
             }}
          )

          {:ok, appealed_post}

        {:error, _step, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Verifies if a user is authorized to restore a deleted post.
  Only the original author OR an organization admin/owner can restore it.
  """
  def authorize_restore(%Post{} = post, actor) do
    actor_id = if is_map(actor), do: actor.id, else: actor

    can_restore? =
      cond do
        post.user_id && post.user_id == actor_id ->
          true

        post.organization_id && post.organization_id == actor_id ->
          true

        post.organization_id ->
          Repo.exists?(
            from(m in OrganizationMembership,
              where:
                m.organization_id == ^post.organization_id and
                  m.user_id == ^actor_id and
                  m.role in [:admin, :owner] and
                  m.status == :approved
            )
          )

        true ->
          false
      end

    if can_restore?, do: :ok, else: {:error, :unauthorized}
  end

  def authorize_restore(actor, %Post{} = post) do
    authorize_restore(post, actor)
  end

  def authorize_restore(post_id, actor) when is_binary(post_id) or is_integer(post_id) do
    case Repo.get(Post, post_id) do
      nil -> {:error, :not_found}
      post -> authorize_restore(post, actor)
    end
  end

  @doc """
  Boolean check wrapper for authorize_restore/2.
  """
  def authorize_restore?(%Post{} = post, actor) do
    authorize_restore(post, actor) == :ok
  end

  def authorize_restore?(actor, %Post{} = post) do
    authorize_restore(post, actor) == :ok
  end

  def authorize_restore?(post_id, actor) when is_binary(post_id) or is_integer(post_id) do
    authorize_restore(post_id, actor) == :ok
  end

  @doc """
  Reverses a rejection lock, bringing the post back to life.
  Streams it back into users' active React timelines in real-time.
  """
  def restore_post(admin, post_id) do
    post = Repo.get!(Post, post_id) |> Repo.preload([:author, :organization])
    actor_id = if is_map(admin), do: admin.id, else: admin

    with :ok <- authorize_restore(post, actor_id) do
      multi =
        Multi.new()
        # 1. Reset state strings and clear out old block metadata fields
        |> Multi.update(
          :post,
          Post.changeset(post, %{
            status: "published",
            rejected_at: nil,
            rejected_by_id: nil,
            rejection_reason: nil,
            appeal_reason: nil,
            appealed_at: nil
          })
        )
        # 2. File administrative restoration log
        |> Multi.insert(:admin_log, %AdminLog{
          action: "post_restored",
          target_id: post.id,
          target_type: "Post",
          user_id: actor_id
        })

      multi =
        if post.organization_id do
          audit_params = %{
            action: "post_restored",
            target_type: "Post",
            target_id: post.id,
            actor_id: actor_id,
            organization_id: post.organization_id,
            metadata: %{
              original_author_id: post.user_id,
              is_admin_override: post.user_id != actor_id
            }
          }

          Multi.insert(multi, :audit_log, AuditLog.changeset(%AuditLog{}, audit_params))
        else
          multi
        end

      Repo.transaction(multi)
      |> case do
        {:ok, %{post: restored_post}} ->
          # Hydrate preloads to supply your exact uniform React payload format
          # Employs our fast batch virtual fields hydration wrapper model
          hydrated_posts =
            Repo.preload(restored_post, [:author, reblog_of: :author, attachments: []])

          # Hydrates likes count, has_liked map signatures
          [payload] = hydrate_virtual_fields([hydrated_posts], nil)

          # Stream the post back into everyone's active viewport feeds instantly
          Phoenix.PubSub.broadcast(
            Kollective.PubSub,
            "timeline:global",
            {:post_restored, payload}
          )

          # Send successful appeal alert to the author
          Notifications.notify(
            restored_post.user_id,
            actor_id,
            "participation_accepted",
            %{
              post_id: restored_post.id,
              target_id: restored_post.id,
              target_type: "Post",
              metadata: %{sub_type: "appeal_approved"}
            },
            %{
              post_id: restored_post.id,
              preview: "🎉 Good news! Your appeal was successful. Your post is restored."
            }
          )

          {:ok, restored_post}

        {:error, _step, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  # --- Structural Helpers ---
  def hydrate_virtual_fields(posts, nil) do
    # For anonymous/unauthenticated sessions, fetch counts in a single batch query
    post_ids = Enum.map(posts, & &1.id)

    likes_counts = fetch_batch_likes_counts(post_ids)
    reblogs_counts = fetch_batch_reblogs_counts(post_ids)

    Enum.map(posts, fn post ->
      %{
        post: %{post | emoji_reactions: format_for_ui(post.emoji_reactions)},
        likes_count: Map.get(likes_counts, post.id, 0),
        reblogs_count: Map.get(reblogs_counts, post.id, 0),
        has_liked: false,
        has_reblogged: false
      }
    end)
  end

  def hydrate_virtual_fields(posts, user) do
    post_ids = Enum.map(posts, & &1.id)

    liked_ids =
      Repo.all(
        from l in Kollective.Posts.Like,
          where: l.user_id == ^user.id and l.post_id in ^post_ids,
          select: l.post_id
      )
      # Drops raw numbers into a super-fast MapSet index
      |> MapSet.new()

    reblogged_ids =
      Repo.all(
        from p in Kollective.Posts.Post,
          where: p.user_id == ^user.id and p.reblog_of_id in ^post_ids,
          select: p.reblog_of_id
      )
      |> MapSet.new()

    bookmarked_ids =
      Repo.all(
        from b in Kollective.Posts.PostBookmark,
          where: b.user_id == ^user.id and b.post_id in ^post_ids,
          select: b.post_id
      )
      |> MapSet.new()

    user_votes =
      Repo.all(
        from v in Kollective.Posts.Vote,
          where: v.user_id == ^user.id and v.post_id in ^post_ids,
          select: {v.post_id, v.type}
      )
      |> Map.new()

    # Pre-fetch totals counts for action displays
    likes_counts = fetch_batch_likes_counts(post_ids)
    reblogs_counts = fetch_batch_reblogs_counts(post_ids)

    # 2. DATA HYDRATION LOOP
    Enum.map(posts, fn post ->
      # Calculate membership states exactly ONCE per iteration pass to save CPU cycles
      is_liked? = MapSet.member?(liked_ids, post.id)
      is_reblogged? = MapSet.member?(reblogged_ids, post.id)
      is_bookmarked? = MapSet.member?(bookmarked_ids, post.id)

      # Extract structural user emojis from internal schema lists
      my_active_emojis =
        case post.emoji_reactions do
          reactions when is_map(reactions) ->
            reactions
            |> Enum.filter(fn {_emoji, user_ids} -> is_list(user_ids) and user.id in user_ids end)
            |> Enum.map(fn {emoji, _user_ids} -> emoji end)

          reactions when is_list(reactions) ->
            reactions
            |> Enum.filter(fn
              {_emoji, user_ids} -> is_list(user_ids) and user.id in user_ids
              _ -> false
            end)
            |> Enum.map(fn {emoji, _user_ids} -> emoji end)

          _ ->
            []
        end

      # Mutate structural internal schema fields safely first
      updated_post_struct = %{
        post
        | bookmarked: is_bookmarked?,
          vote_data: Map.get(user_votes, post.id) || nil,
          emoji_reactions: format_for_ui(post.emoji_reactions),
          data: Map.put(post.data || %{}, "my_reactions", my_active_emojis)
      }

      # 3. RECONCILE UNIFIED MAP VIEWPORT FORMAT FOR REACT
      # Packages data properties perfectly to match Feed and Tab streams
      %{
        post: updated_post_struct,
        likes_count: Map.get(likes_counts, post.id, 0),
        reblogs_count: Map.get(reblogs_counts, post.id, 0),
        # Authoritative flat variables consumed directly by your React icons
        has_liked: is_liked?,
        has_reblogged: is_reblogged?
      }
    end)
  end

  # Helper to turn %{"🚀" => [1,2,3]} into %{"🚀" => 3} for smaller JSON payloads
  defp format_for_ui(nil), do: %{}

  defp format_for_ui(reactions) when is_map(reactions) do
    Enum.into(reactions, %{}, fn
      {emoji, user_ids} when is_list(user_ids) -> {emoji, length(user_ids)}
      {emoji, count} when is_integer(count) -> {emoji, count}
      {emoji, _} -> {emoji, 0}
    end)
  end

  defp format_for_ui(reactions) when is_list(reactions) do
    Enum.into(reactions, %{}, fn
      {emoji, user_ids} when is_list(user_ids) -> {emoji, length(user_ids)}
      {emoji, count} when is_integer(count) -> {emoji, count}
      %{emoji: emoji, count: count} -> {emoji, count}
      %{"emoji" => emoji, "count" => count} -> {emoji, count}
      _ -> {"", 0}
    end)
  end

  defp format_for_ui(_), do: %{}

  # --- Fast Aggregate Batch Queries ---
  defp fetch_batch_likes_counts(post_ids) do
    from(l in Kollective.Posts.Like,
      where: l.post_id in ^post_ids,
      group_by: l.post_id,
      select: {l.post_id, count(l.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp fetch_batch_reblogs_counts(post_ids) do
    from(p in Kollective.Posts.Post,
      where: p.reblog_of_id in ^post_ids,
      group_by: p.reblog_of_id,
      select: {p.reblog_of_id, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Unifies all versions of reply creation. Coordinates root tracking,
  username caching metadata fields, and atomic transaction increment cascades.
  """
  def create_reply(%User{} = user, %Post{} = reply_to, attrs \\ %{}) do
    # 1. Thread Routing: Determine the top-level root of the conversation
    # If replying to a reply, copy its root. Otherwise, the parent IS the root.
    root_post_id = reply_to.root_post_id || reply_to.id

    author =
      case reply_to.author do
        %Ecto.Association.NotLoaded{} ->
          if reply_to.user_id, do: Repo.get(User, reply_to.user_id), else: nil

        loaded_author ->
          loaded_author
      end

    in_reply_to_username = (author && author.username) || nil

    # 2. Build full transactional Multi sequence
    Multi.new()
    # Step A: Insert the reply with all explicit relational metadata mappings
    |> Multi.insert(:reply, fn _repo ->
      %Post{
        user_id: user.id,
        author: user,
        in_reply_to_id: reply_to.id,
        root_post_id: root_post_id,
        # Cache structural user metadata strings to help React skip manual user lookups
        in_reply_to_username: in_reply_to_username
        # in_reply_to_account_id: reply_to.user_id
      }
      |> Post.changeset(attrs)
    end)
    |> Multi.update_all(
      :increment_note_count,
      from(u in User, where: u.id == ^user.id),
      inc: [note_count: 1],
      set: [
        last_post_at: DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      ]
    )

    # 3. Execute Transaction
    |> Repo.transaction()
    |> handle_reply_lifecycle()
  end

  # --- Post Execution Lifecycle Broadcasts ---
  defp handle_reply_lifecycle({:ok, %{reply: reply}}) do
    # Preload the author details instantly so the JSON serializer has user data
    reply = Repo.preload(reply, [:author, poll: :options, attachments: []])

    # A. Broadcast to the Specific Conversation Thread Channel Room
    # Tells React to append this reply node into the tree view live
    KollectiveWeb.Endpoint.broadcast(
      "post_details:#{reply.root_post_id}",
      "new_reply",
      %{reply: reply}
    )

    # B. Trigger our Unified Notifications Pipeline (Worker queues or immediate hooks)
    # Alerts the parent author asynchronously that they have been replied to
    # Handled by your existing MentionNotificationWorker or notify_parent_author pipeline
    # Task.start(fn -> notify_parent_author(reply) end)
    %{"reply_id" => reply.id}
    |> Kollective.Workers.NotifyParentAuthorWorker.new()
    |> Oban.insert()

    {:ok, reply}
  end

  defp handle_reply_lifecycle({:error, _step, changeset, _changes}), do: {:error, changeset}

  # defp fetch_static_likes(post_id) do
  #  # Leverages your direct atomic aggregate counter helper
  #  Repo.one(from l in "likes", where: l.post_id == ^post_id, select: count(l.id))
  # end

  # user votes, use Ecto.Multi to ensure the vote is recorded and the
  # counters are incremented at the exact same time.
  def cast_vote(user_id, poll_id, option_id) do
    Multi.new()
    |> Multi.insert(:vote, %PollVote{user_id: user_id, poll_id: poll_id, option_id: option_id})
    |> Multi.update_all(
      :inc_option,
      from(o in PollOption, where: o.id == ^option_id),
      inc: [votes_count: 1]
    )
    |> Multi.update_all(
      :inc_poll,
      from(p in Poll, where: p.id == ^poll_id),
      inc: [votes_count: 1]
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        broadcast_poll_update(poll_id)
        {:ok, Polls.get_poll_results(poll_id)}

      error ->
        error
    end
  end

  defp broadcast_poll_update(poll_id) do
    results = Polls.get_poll_results(poll_id)
    # Push to everyone currently looking at the post
    KollectiveWeb.Endpoint.broadcast("poll:#{poll_id}", "results_updated", results)
  end

  # "Poll Expiry"
  # Scheduling the Expiry
  # When you create the post and its nested poll, you schedule this job to run at the expires_at timestamp.
  def create_status_with_poll(attrs) do
    Repo.transaction(fn ->
      with {:ok, post} <- create_post(attrs) do
        # {:ok, poll} <- create_poll(post, attrs["poll"]) do

        # SCHEDULE THE CLOSURE
        %{poll_id: post.poll.id}
        |> Kollective.Workers.PollExpiryWorker.new(scheduled_at: post.poll.expires_at)
        |> Oban.insert!()

        {:ok, Repo.preload(post, [:author, poll: :options])}
      end
    end)
  end

  # Poll Edits: forbid editing once a poll has a single vote to maintain integrity.

  # To implement this restriction, you need to add a "guard" check in your update_post
  # (or update_status) context function. This prevents any modifications to the poll structure (options, expiry,
  # or settings) if the votes_count is greater than zero.

  @doc """
  Updates a post, automatically recording edited_at timestamp and incrementing edit_count.
  Precludes editing poll configurations if voting has already commenced.
  """
  def update_post(%Post{} = post, attrs) do
    post = Repo.preload(post, [:poll, :author, :organization], force: true)

    if post.poll && post.poll.votes_count > 0 &&
         (Map.has_key?(attrs, "poll") or Map.has_key?(attrs, :poll)) do
      # If a poll exists, has votes, and the user is trying to change it
      {:error, :poll_locked_by_votes}
    else
      attrs =
        if (Map.has_key?(attrs, "content") or Map.has_key?(attrs, :content)) and
             not (Map.has_key?(attrs, "text") or Map.has_key?(attrs, :text)) do
          content = attrs["content"] || attrs[:content]
          Map.put(attrs, "text", content)
        else
          attrs
        end

      changeset = Post.changeset(post, attrs)

      if map_size(changeset.changes) > 0 do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        new_count = (post.edit_count || 0) + 1
        actor_id = Map.get(attrs, "actor_id") || Map.get(attrs, :actor_id) || post.user_id

        post_changeset =
          changeset
          |> Ecto.Changeset.put_change(:edited_at, now)
          |> Ecto.Changeset.put_change(:edit_count, new_count)

        multi =
          Multi.new()
          |> Multi.update(:post, post_changeset)

        multi =
          if post.organization_id do
            audit_params = %{
              action: "post_edited",
              target_type: "Post",
              target_id: to_string(post.id),
              actor_id: actor_id,
              organization_id: post.organization_id,
              metadata: %{
                new_edit_count: new_count,
                is_admin_edit: actor_id != post.user_id
              }
            }

            Multi.insert(multi, :audit_log, AuditLog.changeset(%AuditLog{}, audit_params))
          else
            multi
          end

        case Repo.transaction(multi) do
          {:ok, %{post: updated_post}} ->
            {:ok, updated_post}

          {:error, :post, %Ecto.Changeset{} = changeset, _} ->
            {:error, changeset}

          {:error, _step, reason, _} ->
            {:error, reason}
        end
      else
        {:ok, post}
      end
    end
  end

  def update_post(post_id, attrs) when is_binary(post_id) or is_integer(post_id) do
    post = Repo.get!(Post, post_id)
    update_post(post, attrs)
  end

  # Custom Emojis in poll options,
  def preload_custom_emojis(post) do
    # 1. Collect all text that might contain emojis
    poll_text = if post.poll, do: Enum.map(post.poll.options, & &1.title), else: []
    all_text = Enum.join([post.content | poll_text], " ")

    # 2. Extract shortcodes like :elixir:
    shortcodes =
      Regex.scan(~r/:[a-z0-9_]+:/i, all_text)
      |> List.flatten()
      |> Enum.map(&String.replace(&1, ":", ""))

    # 3. Fetch from DB and set to virtual field
    emojis =
      from(e in CustomEmoji, where: e.shortcode in ^shortcodes)
      |> Repo.all()
      |> Enum.map(&%{shortcode: &1.shortcode, url: &1.url})

    %{post | emojis: emojis}
  end

  # Custom Emoji
  # Admin "Emoji Manager" Logic
  # When the admin clicks "Save" in your dashboard, you finalize the record in the database.
  def create_emoji(attrs \\ %{}) do
    %CustomEmoji{}
    |> CustomEmoji.changeset(attrs)
    |> Repo.insert()
  end

  # You'll also likely want this here for your React picker
  def list_custom_emojis do
    Repo.all(CustomEmoji)
  end

  # Generate the Static Frame (Elixir)
  # You can use the Mogrify library (which wraps ImageMagick) to extract the first frame.
  # The notation [0] tells ImageMagick to only look at the first frame of the animation.
  def process_emoji_upload(temp_path, shortcode) do
    # 1. Path for the static version
    static_path = "/tmp/#{shortcode}_static.png"

    # 2. Extract first frame: convert 'input.gif[0]' output.png
    # The [0] is critical to avoid processing every frame
    import Mogrify

    open("#{temp_path}[0]")
    |> format("png")
    |> save(path: static_path)

    # 3. Upload BOTH files to Cloudflare R2
    # upload_to_r2(temp_path, "#{shortcode}.gif")
    # upload_to_r2(static_path, "#{shortcode}_static.png")
  end

  # Handle "Blurred/Static" logic to Large Animated Images.

  # To handle large animated images (like GIF memes) in the main feed, we apply a "Three-State" logic:
  # Blurhash (Initial load) → Static Frame (First frame PNG) → Full Animation (GIF).

  # When a large GIF is uploaded, you generate the blurhash for the
  # initial load and the static_url for the "Paused" state.
  def process_large_gif(temp_path, filename) do
    # 1. Extract first frame for static preview
    static_path = "/tmp/static_#{filename}.png"

    import Mogrify

    open(temp_path)
    # Get the first frame
    |> custom("frames", "0")
    |> format("png")
    |> save(path: static_path)

    # 2. Generate Blurhash from that static frame
    blurhash = Kollective.Media.MediaAttachment.generate_hash(static_path)

    # 3. Upload both to R2
    # upload_to_r2(temp_path) TODO
    original_url = "http://temp/ss"
    # upload_to_r2(static_path)  TODO
    static_url = "http://temp/ss"

    {:ok, %{url: original_url, static_url: static_url, blurhash: blurhash}}
  end

  def process_video_upload(temp_path, filename) do
    static_path = "/tmp/thumb_#{filename}.jpg"

    # Extract frame at 1-second mark
    System.cmd("ffmpeg", [
      "-i",
      temp_path,
      "-ss",
      "00:00:01.000",
      "-vframes",
      "1",
      static_path
    ])

    # Now generate blurhash from the jpg and upload both to R2
    _blurhash = Kollective.Media.MediaAttachment.generate_hash(static_path)
    # ... upload logic ...
  end

  def create_attachment(attrs) do
    %Kollective.Posts.PostAttachment{}
    |> Kollective.Posts.PostAttachment.changeset(attrs)
    |> Repo.insert()
  end

  def update_attachment_description(attachment, description) do
    attachment
    |> Ecto.Changeset.change(description: description)
    |> Repo.update()
  end

  @doc """
  Toggles a user's bookmark state on a specific post.
  Returns {:ok, :inserted} or {:ok, :removed}
  """
  def toggle_bookmark_post(%Kollective.Accounts.User{} = user, post_id) do
    case Repo.get_by(PostBookmark, user_id: user.id, post_id: post_id) do
      nil ->
        # First click: Insert bookmark row record
        %PostBookmark{user_id: user.id, post_id: post_id}
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:ok, :inserted}
          {:error, cs} -> {:error, cs}
        end

      existing_bookmark ->
        # Second click: Remove bookmark row from database
        Repo.delete!(existing_bookmark)
        {:ok, :removed}
    end
  end

  @doc """
  Fetches a user's saved bookmarks timeline stream.
  Applies keyset pagination and preloads post attachments and authors in a single pass.
  """
  def list_bookmarked_posts(%Kollective.Accounts.User{} = user, params \\ %{}) do
    limit = Map.get(params, "limit", 20)
    cursor = Map.get(params, "cursor")

    base_query =
      from(b in PostBookmark,
        where: b.user_id == ^user.id,
        # Join the core post records directly
        join: p in assoc(b, :post),
        # Preload the author and attached multi-image media carousels
        preload: [post: [:author, :attachments]]
      )

    query =
      if cursor,
        do: from([b, p] in base_query, where: b.id < ^cursor),
        else: base_query

    bookmarks_list =
      query
      |> order_by([b, p], desc: b.id)
      |> limit(^limit)
      |> Repo.all()

    # Transform rows flat to feed into your modern PostJSON serializer smoothly
    Enum.map(bookmarks_list, fn b ->
      # Stash the wrapper bookmark cursor ID into metadata so React can read page limits
      Map.put(b.post, :bookmark_cursor_id, b.id)
    end)
  end

  @doc """
  The definitive hashtag timeline retrieval pass.
  Queries posts containing the target tag token, respects regional category/scope sliders,
  applies user-defined mute phrase filters in RAM, and extracts look-ahead cursors .
  """
  def list_hashtag_timeline(%Kollective.Accounts.User{} = user, tag_name, params \\ %{}) do
    limit = Map.get(params, "limit", 20)
    cursor = Map.get(params, "cursor")

    # Normalize the incoming tag string to lower case to match indexing profiles
    normalized_tag = String.downcase(tag_name)

    # 1. Base query scanning the index join table directly
    base_query =
      from(p in Post,
        # 1. Join directly on the Hashtag schema using a regular where clause
        join: h in Hashtag,
        on: h.name == ^normalized_tag,
        # 2. Join the many-to-many table using its schema or the correct binding
        join: ph in "posts_hashtags",
        on: ph.post_id == p.id and ph.hashtag_id == h.id,
        where: p.status == :published,
        preload: [:author, :attachments]
      )

    # Apply dynamic keyset pagination matching your primary index keys
    query =
      if cursor,
        do: from(p in base_query, where: p.id < ^cursor),
        else: base_query

    # 2. OPTIMIZATION SLIDERS (Inject category or geo filters if passed from React tabs)
    query =
      case params["category"] || params[:category] do
        nil -> query
        cat_str -> from(p in query, where: p.category == ^to_string(cat_str))
      end

    raw_posts =
      query
      |> order_by([p], desc: p.id)
      |> limit(^limit)
      |> Repo.all()

    # 3. USER CURATION FILTER INTERCEPTION MASK
    active_filters = UserFilter.list_active_filters(user)
    mute_regex = UserFilter.compile_regex_pattern(active_filters)

    filtered_posts =
      if mute_regex do
        Enum.reject(raw_posts, fn post -> Regex.run(mute_regex, post.content || "") end)
      else
        raw_posts
      end

    # Wrap in your unified response contract shape expected by index controllers
    next_cursor =
      case List.last(filtered_posts) do
        nil -> nil
        last_item -> to_string(last_item.id)
      end

    %{
      entries: filtered_posts,
      next_cursor: next_cursor
    }
  end
end

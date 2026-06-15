defmodule Kollective.Posts.Posts do
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Ecto.Multi
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Users
  alias Kollective.Posts.Post
  alias Kollective.Posts.Like
  alias Kollective.Posts.Repost
  alias Kollective.Accounts.UserRelationship
  alias Kollective.Notifications.Notifications
  alias Kollective.Hashtags.Hashtag
  alias Kollective.Posts.ThreadMute

  alias Kollective.Workers.{PublishPostWorker, PollExpiryWorker, VideoTranscoder, MentionNotificationWorker}

  alias Kollective.Polls.Polls
  alias Kollective.Polls.Poll
  alias Kollective.Polls.PollVote
  alias Kollective.Polls.PollOption
  alias Kollective.Posts.CustomEmoji

  alias Scrivener

  def list_local_feed(user, params) do
    Post
    |> where([p],
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
  defp common_feed_pipeline(query, user, params) do
    query
    |> order_by([p], desc: p.inserted_at)
    |> Scrivener.paginate(page: params["page"] || 1, repo: Repo)
    |> then(fn page ->
      # We preload ONLY for the entries on the current page
      %{page | entries: Repo.preload(page.entries, [
        :user,
        :attachments,
        # Only preload the current user's repost record to show "Active" state
        reposts: from(r in Repost, where: r.user_id == ^user.id)
      ])}
    end)
  end

  # Ring 1: Specific Local Districts (L1, L2, L3)
  defp base_local_query(user) do
    from p in Post,
      where: p.origin_district_l1 == ^user.district_l1_id or
             p.origin_district_l2 == ^user.district_l2_id or
             p.origin_district_l3 == ^user.district_l3_id
  end

  # Ring 2: Same State, but EXCLUDE Local Districts
  defp base_state_query(user) do
    from p in Post,
      where: p.origin_state == ^user.state and
             p.origin_district_l1 != ^user.district_l1_id and
             p.origin_district_l2 != ^user.district_l2_id and
             p.origin_district_l3 != ^user.district_l3_id
  end

  # Ring 3: Same Country, but EXCLUDE State
  defp base_country_query(user) do
    from p in Post,
      where: p.origin_country == ^user.country and
             p.origin_state != ^user.state
  end

  # Ring 4: Outside Country
  defp base_world_query(user) do
    from p in Post,
      where: p.origin_country != ^user.country
  end

  @spec has_unread_posts?(any(), :country | :local | :state | :world) :: boolean()
  def has_unread_posts?(user, scope) do
    query = case scope do
      :local -> base_local_query(user)
      :state -> base_state_query(user)
      :country -> base_country_query(user)
      :world -> base_world_query(user)
    end

    query
    |> where([p], p.inserted_at > ^user.last_read_at)
    |> Repo.exists?() # Efficiently returns true/false
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
    |> with_cte("thread", as: ^initial_query) # Simplification for example
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
    posts_by_parent = Enum.group_by(posts, & &1.in_reply_to_id)
    #posts_by_parent = Enum.group_by(posts, fn %{post: p} -> p.in_reply_to_id end)

    # Start building from the top-level posts (where in_reply_to_id is nil)
    nest_posts(posts_by_parent[nil], posts_by_parent)
  end

  defp nest_posts(nil, _), do: []
  defp nest_posts(posts, mapping) do
    Enum.map(posts, fn post ->
      # Recursively attach replies to each post
      # Recursively find replies for this specific item's post ID
      replies = nest_posts(mapping[post.id], mapping)

      # Put the replies into the map so React can find them
      Map.put(post, :replies, replies)
    end)
  end

  @doc """
  Unifies all pipeline variants for creating a post, including targeting overrides,
  content scrubbing, threading, atomic hashtag mappings, mention hooks, and media hooks.
  """
  def create_post(%User{} = user, attrs \\ %{}) do
    # 1. Resolve content parameter safety and metadata state variants
    content = attrs["content"] || attrs[:content] || ""
    is_reply = not is_nil(attrs["in_reply_to_id"] || attrs[:in_reply_to_id])

    # 2. Extract references & metadata outside of transaction engine
    tag_names = extract_hashtags(content)
    mentioned_usernames = parse_mention_strings(content)

    # 3. Determine safety layout (Shadowban checks / Restricted Keyword processing)
    is_restricted = user.is_shadow_banned || contains_restricted_words?(content)
    initial_status = if is_restricted, do: "pending", else: "published"

    # 4. Thread routing: Identify immediate parent context & long-term root_post_id
    attrs = append_threading_context(attrs)

    # 5. Build full transactional Multi sequence
    Multi.new()
    # 1. Initial Schema Insertion with Core Properties & Geographic Targeting
    # Base Post Insert & Geo Targeting
    |> Multi.insert(:post, fn _repo ->
      %Post{user_id: user.id, author: user, status: initial_status}
      |> Post.changeset(attrs)
      |> validate_and_fix_targeting(user)
    end)

    # 2. Parse and Upsert Global Hashtags
    # Extract and Upsert Hashtags
    |> Multi.run(:hashtags, fn _repo, %{post: post} ->
      tags = upsert_hashtag_entities(tag_names)

      post
      |> Repo.preload(:hashtags)
      |> Post.changeset(%{})
      |> Ecto.Changeset.put_assoc(:hashtags, tags)
      |> Repo.update()
    end)

    # 3. Isolate Verified Mentions, Register Database Notifications, Link UI Fields
    # Synchronize UI Mention Array Field Data Structure (No long text parsing in React)
    |> Multi.run(:notifications_and_mentions, fn _repo, %{hashtags: post} ->
      # Filter for matching database entities
      verified_mentions = Kollective.Accounts.list_users_by_usernames(mentioned_usernames)

      #parent_author_id = get_parent_author_id(post)

      # Register structural notify hooks for mentions
      #register_mention_notifications(post, verified_mentions, parent_author_id)

      # Register structural notify hook for parent author reply tracking
      #if is_reply, do: notify_parent_author(post)

      # Save static serialization layout block to avoid complex extraction loops inside React UI
      post
      |> Ecto.Changeset.change(mentions: Enum.map(verified_mentions, & %{id: &1.id, username: &1.username}))
      |> Repo.update()
    end)

    # 4. Media Handling Layout Support (Waffle file mappings)
    |> Multi.run(:media_upload, fn _repo, %{notifications_and_mentions: post} ->
      if attrs["media"] do
        post
        |> Post.changeset(%{media: attrs["media"]})
        |> Repo.update()
      else
        {:ok, post}
      end
    end)

    # 5. ASYNC LIFECYCLE SCHEDULING (Queue up Oban Jobs inside the Transaction)
    |> Multi.run(:oban_jobs, fn _repo, %{media_upload: post} ->
      # Preload attachments to safely inspect content_types
      post = Repo.preload(post, :attachments)

      # A. Video Transcoding Worker Queue (Safer than Task.start)
      post.attachments
      |> Enum.filter(&String.starts_with?(&1.content_type || "", "video"))
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

        # C. Send immediate reply tracking push if this is a chronological thread reply
        if is_reply, do: notify_parent_author(post)
      end

      # D. Schedule Future Post Date Actions
      if Map.has_key?(attrs, "published_at") && DateTime.compare(post.published_at, DateTime.utc_now()) == :gt do
        %{post_id: post.id}
        |> PublishPostWorker.new(scheduled_at: post.published_at)
        |> Oban.insert!()
      end

      # E. Schedule Poll Expiry Closures
      if post.poll do
        %{poll_id: post.poll.id}
        |> PollExpiryWorker.new(scheduled_at: post.poll.expires_at)
        |> Oban.insert!()
      end

      {:ok, post}
    end)
    # Execution Transaction Engine Block
    |> Repo.transaction()
    |> handle_lifecycle_broadcasts()
  end

  # helpers
  defp append_threading_context(attrs) do
    case attrs["in_reply_to_id"] || attrs[:in_reply_to_id] do
      nil -> attrs
      reply_id ->
        case Repo.get(Post, reply_id) do
          nil -> attrs
          parent ->
            root_id = parent.root_post_id || parent.id
            attrs
            |> Map.put("root_post_id", root_id)
            |> Map.put("parent_id", parent.id)
        end
    end
  end

  defp validate_and_fix_targeting(changeset, user) do
    organization_id = Ecto.Changeset.get_field(changeset, :organization_id)

    case user.type do
      :regular ->
        changeset
        |> Ecto.Changeset.put_change(:origin_country, user.country)
        |> Ecto.Changeset.put_change(:origin_state, user.state)
        |> Ecto.Changeset.put_change(:origin_city_id, user.city_id)
        |> Ecto.Changeset.put_change(:origin_federal_district, user.federal_district)
        |> Ecto.Changeset.put_change(:origin_state_senate_district, user.state_senate_district)
        |> Ecto.Changeset.put_change(:origin_state_district, user.state_district)

      type when type in [:scholar, :journalist] or not is_nil(organization_id) ->
        changeset
        |> default_value(:origin_country, user.country)
        |> default_value(:origin_state, user.state)
    end
  end

  defp default_value(changeset, field, value) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil -> Ecto.Changeset.put_change(changeset, field, value)
      _ -> changeset
    end
  end

  defp upsert_hashtag_entities(tag_names) do
    Enum.map(tag_names, fn name ->
      Repo.insert!(
        %Hashtag{name: name},
        on_conflict: [set: [name: name]],
        conflict_target: :name
      )
    end)
  end

  defp register_mention_notifications(post, verified_mentions, parent_author_id) do
    Enum.each(verified_mentions, fn recipient ->
      if recipient.id != post.user_id && recipient.id != parent_author_id do
        {:ok, notification} = Kollective.Notifications.create_notification(%{
          user_id: recipient.id,
          actor_id: post.user_id,
          post_id: post.id,
          type: "mention"
        })

        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "user_notifications:#{recipient.id}",
          {:new_notification, notification}
        )
      end
    end)
  end

  defp notify_parent_author(post) do
    if post.parent_id do
      parent = Repo.get(Post, post.parent_id)

      if parent && parent.user_id != post.user_id do
        Kollective.Notifications.create_notification(%{
          user_id: parent.user_id,
          actor_id: post.user_id,
          post_id: post.id,
          type: "reply"
        })
      end
    end
  end

  # Post Execution Real-Time WebSocket Broadcasting Orchestrator
  defp handle_lifecycle_broadcasts({:ok, %{oban_jobs: post}}) do
    if post.category == :voice do
      Phoenix.PubSub.broadcast(Kollective.PubSub, "voice_alerts", {:new_voice_post, post})
    end

    broadcast_feed_updates(post)

    {:ok, Repo.preload(post, [:author, poll: :options, attachments: []])}
  end
  defp handle_lifecycle_broadcasts({:error, _step, changeset, _changes}), do: {:error, changeset}

  defp handle_lifecycle_resultsX({:ok, %{media_upload: post}}, _) do
    # 1. Asynchronous Video Trancoding Layer
    if post.media_type == "video" do
      Task.start(fn -> process_video_background(post.id) end)
    end

    # 2. Real-time Category Routing Alert Pushes (Voice / Standard PubSub logs)
    if post.category == :voice do
      Phoenix.PubSub.broadcast(Kollective.PubSub, "voice_alerts", {:new_voice_post, post})
    end

    # 3. Geo-Fenced & Federated Public Room Broadcasters
    broadcast_feed_updates(post)

    # 4. Standard Context Payload Preloads for Controller Delivery Pipeline
    {:ok, Repo.preload(post, [:author, poll: :options])}
  end
  defp handle_lifecycle_results({:error, _step, changeset, _changes}, _), do: {:error, changeset}

  defp process_video_background(post_id) do
    post = Repo.get!(Post, post_id)

    # Update status to processing for React UI
    post |> Ecto.Changeset.change(processing_status: :processing) |> Repo.update!()

    # ... FFmpeg or Transcoding logic happens here ...
    # ... Transcoding / Thumbnail logic (FFmpeg) here ...
    # 2. Paths for FFmpeg
    # We get the local path of the original video
    video_path = MediaUploader.storage_path(:original, {post.media, post})
    thumb_path = Path.rootname(video_path) <> "_thumb.jpg"

    # 3. Run FFmpeg command
    # Video thumbnail extraction example (capture a frame at 1 second):
    # -i: input, -ss: seek to 1s, -vframes: 1 frame, -q:v: quality
    # Video Processing with Thumbnail Extraction
    case System.cmd("ffmpeg", ["-i", video_path, "-ss", "00:00:01.000", "-vframes", "1", thumb_path, "-y"]) do
      {_, 0} ->
        # 4. Success: Update status and metadata with thumbnail path
        metadata = Map.put(post.metadata || %{}, "thumbnail_path", Path.basename(thumb_path))

        {:ok, final_post} =
          post
          |> Ecto.Changeset.change(processing_status: :completed, metadata: metadata)
          |> Repo.update()

        # 5. Broadcast the final post to React
        # Finalize and alert the frontend via PubSub
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "post_details:#{post_id}",
          {:video_ready, final_post}
        )

      {error, _} ->
        # Handle failure
        post |> Ecto.Changeset.change(processing_status: :failed) |> Repo.update()
        IO.inspect(error, label: "FFmpeg Error")
    end
  end

  defp broadcast_feed_updates(post) do
    if post.visibility == "public" && post.status == "published" do
      # Feed Real-Time Engine Routing
      Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:new_post, post})
      Phoenix.PubSub.broadcast(Kollective.PubSub, "discovery_updates", {:new_discovery_post, post})

      # Micro-Targeting Discovery Channels
      local_topic = "discovery:local:#{post.origin_state}:#{post.origin_federal_district}"
      KollectiveWeb.Endpoint.broadcast(local_topic, "new_post", %{post: post})

      if post.target_scope in [:state, :country, :world] do
        state_topic = "discovery:state:#{post.origin_state}"
        KollectiveWeb.Endpoint.broadcast(state_topic, "new_post", %{post: post})
      end
    end
  end

  defp contains_restricted_words?(content) do
    keywords = Kollective.Moderation.Moderations.list_restricted_keywords()
    Enum.any?(keywords, fn k -> String.contains?(String.downcase(content), String.downcase(k.word)) end)
  end

  defp parse_mention_strings(text) do
    Regex.scan(~r/@[[:alnum:]_]+/, text)
    |> List.flatten()
    |> Enum.map(&String.replace(&1, "@", ""))
    |> Enum.uniq()
end

  defp get_parent_author_id(post) do
    if post.parent_id, do: Repo.get(Post, post.parent_id).user_id, else: nil
  end

  defp post_id_from_multi(step) do
    # Fallback accessor for background processes safely decoupled from structural mutations
    step
  end

  # CREATE: Just pass parent_id and in_reply_to_id in the attrs
  def create_postO(attrs \\ %{}) do
    # 1. Extract tag names from content: ["elixir", "coding"]
    tag_names = extract_hashtags(attrs["content"])

    # 2. Convert names into Hashtag structs (Get or Create)
    hashtags = Enum.map(tag_names, &get_or_create_hashtag/1)

    # 3. Identify the 'root_post_id' based on the reply target
    attrs =
      case attrs["in_reply_to_id"] || attrs[:in_reply_to_id] do
        nil ->
          # Not a reply? This post is its own root (or root is nil)
          attrs

        reply_id ->
          # It's a reply! Find the root of the post we are replying to
          case Repo.get(Post, reply_id) do
            nil -> attrs # Handle error: parent doesn't exist
            parent ->
              # If parent already has a root, use it. Otherwise, parent IS the root.
              root_id = parent.root_post_id || parent.id
              Map.put(attrs, "root_post_id", root_id)
          end
      end

    %Post{}
    |> Post.changeset(attrs)
    # Tell Ecto to handle the "posts_hashtags" table for you
    |> Ecto.Changeset.put_assoc(:hashtags, hashtags)
    |> Repo.insert()
    # Optional: preload the author after creation so the
    # JSON response includes user details immediately.
    |> case do
      {:ok, post} ->
        # If a poll was included, schedule the Oban expiry job
        if post.poll do
          %{poll_id: post.poll.id}

          |> Kollective.Workers.PollExpiryWorker.new(scheduled_at: post.poll.expires_at)
          |> Oban.insert!()
        end

        # If scheduled for the future, tell Oban to run the worker then
        # 1. Handle Scheduling (Oban)
        if DateTime.compare(post.published_at, DateTime.utc_now()) == :gt do
          %{post_id: post.id}

          |> Kollective.Workers.PublishPostWorker.new(scheduled_at: post.published_at)
          |> Oban.insert!()
        else
          # If the scheduled time is in the past, publish immediately
          # Kollective.Workers.PublishPostWorker.new(%{"post_id" => post.id})
          #|> Oban.insert()

          # Broadcast ONLY the small metadata or ID to the public
          KollectiveWeb.Endpoint.broadcast("feed:public", "new_post_available", %{
            id: post.id,
            author: post.author.username
          })
        end

        # Run this in the background or after the return
        #Task.start(fn -> notify_mentioned_users(post) end) #CHECK LATER
        # 2. RETURN THE PRELOADED POST
        # This ensures the Controller/JSON View has the user data
        {:ok, Repo.preload(post, :author, poll: :options)}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  # LIST: Fetches posts and nests them for JSON delivery
  def list_posts_as_tree do
    Post
    |> preload(:author) # <--- Fetch user data (username, avatar, etc.)
    |> order_by(asc: :inserted_at) # Keeps conversation order
    |> Repo.all()
    |> build_tree() # Uses the build_tree function from above
  end

  def list_posts_with_likes do
    from(p in Post,
      left_join: l in assoc(p, :likes),
      group_by: p.id,
      # Use select_merge to fill the virtual field
      select_merge: %{likes_count: count(l.id)} # Calculates total likes
    )

    |> preload([:author, :root_post])
    |> Repo.all()
    |> build_tree() # Your existing tree-building logic
  end

  # POST `/api/posts/${postId}/like`
  def toggle_like(user_id, post_id) do
    # Look for an existing like by this user for this post
    like_query = from(l in Kollective.Posts.Like, where: l.user_id == ^user_id and l.post_id == ^post_id)

    case Repo.one(like_query) do
      nil -> # User hasn't liked yet: Create it
        %Kollective.Posts.Like{}

        |> Kollective.Posts.Like.changeset(%{user_id: user_id, post_id: post_id})
        |> Repo.insert()

      like ->
        # User already liked: Remove it (Unlike)
        Repo.delete(like)
    end
  end

  #To get the like count immediately after a click without re-fetching the whole tree, use this helper
  def get_like_count(post_id) do
    query = from l in Like,
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
        where: p.user_id not in ^hidden_ids, # Exclude blocked/muted users
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

  #you now have the root_post_id saved on every reply, you no longer need the complex recursive CTE
  # for most cases. You can fetch a massive 500-post conversation with a single, high-performance database hit.

  #The "Flat" Thread Query
  # This query fetches the original post plus every reply that shares that same root_post_id.
  def get_thread(post_id, current_user_id \\ nil) do
    # We look for the post itself OR any post that points to it as the root
    query =
      from p in Post,
        where: p.id == ^post_id or p.root_post_id == ^post_id,
        left_join: total_l in assoc(p, :likes),
        left_join: user_l in "likes",
          on: user_l.post_id == p.id and user_l.user_id == ^current_user_id,
        group_by: [p.id, user_l.id],
        preload: [:author],
        order_by: [asc: p.inserted_at], # Keeps conversation chronological
        select: {p, count(total_l.id), not is_nil(user_l.id)}

    Repo.all(query)

    |> Enum.map(fn {post, count, liked} ->
      %{post: post, likes_count: count, has_liked: liked}
    end)
    |> build_tree() # Turn the flat list into the React-ready tree
  end

  # Fetch everything belonging to the same root, regardless of where you start
  def get_context(post) do
    root_id = post.root_post_id || post.id
    get_thread(root_id)
  end

  #Because the database handles the "cleanup" of the replies, your Elixir code stays extremely simple.
  #You just delete the one post, and Postgres handles the rest in a single transaction.
  def delete_post(%Post{} = post) do
    # This single call will trigger the database to wipe out
    # every reply and every nested reply automatically.
    Repo.delete(post)
  end

  #Reblog:

  def reblog_post(user_id, post_id) do
    original_post = Repo.get!(Post, post_id)

    # Check if user is trying to reblog their own content
    if original_post.author_id == user_id do
      {:error, :self_reblog_not_allowed}
    else
      # ... your existing Multi logic for toggle ...
      reblog_post_sub(user_id, post_id)
    end
  end

  def reblog_post_sub(user_id, post_id) do
    existing = Repo.get_by(Post, author_id: user_id, reblog_of_id: post_id)

    if existing do
      # --- UNDO REBLOG LOGIC ---
      Multi.new()
      |> Multi.delete(:reblog, existing)
      |> Multi.update_all(:decrement_counter,
        from(p in Post, where: p.id == ^post_id),
        inc: [reblogs_count: -1] # Decrement by 1
      )

      |> Repo.transaction()
    else
      # Create logic
      case execute_create_reblog(user_id, post_id) do
        {:ok, %{reblog: reblog}} ->
          # TRIGGER NOTIFICATION HERE
          # #Reblog_post function to trigger a notification only when a
          # new boost is created (not when it's undone).
          notify_reblog(reblog)
          {:ok, reblog}
        error -> error
      end
    end
  end

  def execute_create_reblog(user_id, post_id) do
    # --- CREATE REBLOG LOGIC ---
    Multi.new()
    |> Multi.insert(:reblog, %Post{
      user_id: user_id,
      reblog_of_id: post_id,
      content: nil # Use your :content field
    })
    |> Multi.update_all(:increment_counter,
      from(p in Post, where: p.id == ^post_id),
      inc: [reblogs_count: 1] # Increment by 1
    )
    |> Repo.transaction()
  end

  # Notifications so a user knows when their post has been reblogged
  defp notify_reblog(reblog) do
    # 1. Fetch the original post to find the owner
    original_post = Repo.get!(Post, reblog.reblog_of_id) |> Repo.preload(:author)
    _reblog_author = Repo.get!(User, reblog.user_id)

    # Avoid notifying yourself if you somehow boost your own post
    if original_post.user_id != reblog.user_id do
      # 2. Save to Database for history
      {:ok, _notif} = Notifications.create_action_notification(
        original_post.user_id,
        reblog.user_id,
        original_post.id,
        "reblog"
      )

      # 3. Broadcast real-time via Phoenix Channels
      #KollectiveWeb.Endpoint.broadcast(
      #  "notifications:#{original_post.user_id}",
      #  "new_reblog",
      #  %{
      #    who: reblog_author.username,
      #    post_id: original_post.id,
      #    content_preview: String.slice(original_post.content || "", 0, 30)
      #  }
      #)

    end
  end

  def reblog_postO(user_id, post_id) do
    original_post = Repo.get!(Post, post_id)

    # Check if user is trying to reblog their own content
    if original_post.author_id == user_id do
      {:error, :self_reblog_not_allowed}
    else
      # ... your existing Multi logic for toggle ...
      execute_reblog_toggle(user_id, post_id)
    end
  end

  def execute_reblog_toggle(user_id, post_id) do
    existing = Repo.get_by(Post, author_id: user_id, reblog_of_id: post_id)

    if existing do
      # --- UNDO REBLOG LOGIC ---
      Multi.new()

      |> Multi.delete(:reblog, existing)
      |> Multi.update_all(:decrement_counter,
        from(p in Post, where: p.id == ^post_id),
        inc: [reblogs_count: -1] # Decrement by 1
      )

      |> Repo.transaction()
    else
      # --- CREATE REBLOG LOGIC ---
      Multi.new()
      |> Multi.insert(:reblog, %Post{
        user_id: user_id,
        reblog_of_id: post_id,
        content: nil # Use your :content field
      })
      |> Multi.update_all(:increment_counter,
        from(p in Post, where: p.id == ^post_id),
        inc: [reblogs_count: 1] # Increment by 1
      )
      |> Repo.transaction()
    end
  end

  def get_reblog_count(post_id) do
    Post
    |> where([p], p.id == ^post_id)
    |> select([p], p.reblogs_count)
    |> Repo.one() || 0
  end

  # When fetching a user's feed, you must preload the reblog_of post and its author,
  #or React won't have anything to display.
  def list_timeline(user_id) do
    Post
    |> where([p], p.author_id == ^user_id)
    |> preload([:author, reblog_of: :author]) # Deep preload
    |> Repo.all()
  end

  #Mentions
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
      # 1. Save to DB (for history)
      {:ok, _notif} = Notifications.create_action_notification(
        user.id,
        post.author_id,
        post.id,
        "mention"
      )

      # 2. Push to Phoenix Channel (Real-time!)
      #Endpoint.broadcast("notifications:#{user.id}", "new_mention", %{
      #  from: post.author.username,
      #  post_id: post.id,
      #  excerpt: String.slice(post.content, 0, 50)
      #})
    end)
  end

  # Function that inserts a new post record where the content is empty but the reblog_of_id is set
  def repost_post(user_id, post_id) do
    # Mastodon style: If it already exists, "un-repost" it (toggle)
    case Repo.get_by(Post, author_id: user_id, reblog_of_id: post_id) do
      nil ->
        %Post{}

        |> Post.changeset(%{
          author_id: user_id,
          reblog_of_id: post_id,
          content: nil # Pure reposts have no content
        })
        |> Repo.insert()
      existing ->
        Repo.delete(existing)
    end
  end

  def extract_hashtagsX(content) do
    ~r/#[[:alnum:]_]+/u

    |> Regex.scan(content)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(&String.replace(&1, "#", "")) # Store without the '#'
  end

  defp extract_hashtags(text) do
    Regex.scan(~r/#[[:alnum:]_]+/, text)
    |> List.flatten()
    |> Enum.map(&String.downcase(String.replace(&1, "#", "")))
    |> Enum.uniq()
  end

  def get_or_create_hashtag(name) do
    # Standardize to lowercase (so #Elixir and #elixir are the same)
    name = String.downcase(name)

    %Hashtag{name: name}

    |> Hashtag.changeset(%{}) # Just to ensure it's valid
    |> Repo.insert(
      on_conflict: [set: [name: name]], # If it exists, just "update" the name (do nothing)
      conflict_target: :name,
      returning: true
    )
    |> case do
      {:ok, hashtag} -> hashtag
      {:error, _} -> Repo.get_by!(Hashtag, name: name) # Fallback if insert fails
    end
  end

  def list_posts_with_tags do
    Post

    |> preload([:author, :hashtags]) # <--- Fetches the tags
    |> Repo.all()
  end

  #infinite scrolling
  def list_posts(params \\ %{}) do
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
    query = from tm in ThreadMute,
      where: tm.user_id == ^user_id and tm.root_post_id == ^root_post_id

    case Repo.one(query) do
      nil ->
        # User wants to silence this conversation
        %ThreadMute{}

        |> ThreadMute.changeset(%{user_id: user_id, root_post_id: root_post_id})
        |> Repo.insert()

      mute ->
        # User wants to hear from this conversation again
        Repo.delete(mute)
    end
  end

  #use fragment to access the Postgres @@ match operator. We use websearch_to_tsquery because it allows users to
  #use familiar syntax like quotes for phrases or minus signs to exclude words
  def search_posts(query_string) do
    from p in Post,
      where: fragment("searchable @@ websearch_to_tsquery(?)", ^query_string),
      # Rank results so the most relevant matches appear first
      order_by: [desc: fragment("ts_rank_cd(searchable, websearch_to_tsquery(?))", ^query_string)],
      preload: [:author],
      limit: 20
  end

  # user votes, use Ecto.Multi to ensure the vote is recorded and the
  # counters are incremented at the exact same time.
  def cast_vote(user_id, poll_id, option_id) do
    Multi.new()

    |> Multi.insert(:vote, %PollVote{user_id: user_id, poll_id: poll_id, option_id: option_id})
    |> Multi.update_all(:inc_option,
        from(o in PollOption, where: o.id == ^option_id), inc: [votes_count: 1])

    |> Multi.update_all(:inc_poll,
        from(p in Poll, where: p.id == ^poll_id), inc: [votes_count: 1])
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        broadcast_poll_update(poll_id)
        {:ok, Polls.get_poll_results(poll_id)}
      error -> error
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

  # Check the poll's status before allowing the update transaction to proceed.
  def update_post(post_id, attrs) do
    post = Repo.get!(Post, post_id) |> Repo.preload(:poll)

    if post.poll && post.poll.votes_count > 0 && Map.has_key?(attrs, "poll") do
      # If a poll exists, has votes, and the user is trying to change it
      {:error, :poll_locked_by_votes}
    else
      # Proceed with the normal update logic
      post

      |> Post.changeset(attrs)
      |> Repo.update()
    end
  end

  #Custom Emojis in poll options,
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
      |> Enum.map(& %{shortcode: &1.shortcode, url: &1.url})

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

  #When a large GIF is uploaded, you generate the blurhash for the
  #initial load and the static_url for the "Paused" state.
  def process_large_gif(temp_path, filename) do
    # 1. Extract first frame for static preview
    static_path = "/tmp/static_#{filename}.png"

    import Mogrify
    open(temp_path)

    |> custom("frames", "0") # Get the first frame
    |> format("png")
    |> save(path: static_path)

    # 2. Generate Blurhash from that static frame
    blurhash = Kollective.Media.MediaAttachment.generate_hash(static_path)

    # 3. Upload both to R2
     original_url = "http://temp/ss" #upload_to_r2(temp_path) TODO
     static_url = "http://temp/ss" #upload_to_r2(static_path)  TODO

    {:ok, %{url: original_url, static_url: static_url, blurhash: blurhash}}
  end

  def process_video_upload(temp_path, filename) do
    static_path = "/tmp/thumb_#{filename}.jpg"

    # Extract frame at 1-second mark
    System.cmd("ffmpeg", [
      "-i", temp_path,
      "-ss", "00:00:01.000",
      "-vframes", "1",
      static_path
    ])

    # Now generate blurhash from the jpg and upload both to R2
    _blurhash = Kollective.Media.MediaAttachment.generate_hash(static_path)
    # ... upload logic ...
  end


end

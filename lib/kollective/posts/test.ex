i do not use Activity Pub anymore. i have various versions of "create_post" function created for various features. help me merge them all into one unified function with all features,
i'll share code in multiple parts, so please wait after each prompt:

  def create_post(attrs \\ %{}) do
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

  # LIST: Fetch

  def create_post(user, attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> put_change(:user_id, user.id)
    |> Repo.insert()
    |> broadcast_if_voice() # <--- Trigger the real-time logic
  end

  defp broadcast_if_voice({:ok, post} = result) do
    if post.category == :voice do
      # Pushes a notification to all listeners on the 'voice_alerts' topic
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "voice_alerts",
        {:new_voice_post, post}
      )
    end
    result
  end
  defp broadcast_if_voice(error), do: error



  def create_post(user, attrs) do
    Ecto.Multi.new()
    # 1. Initial Insert (Content, Category, Visibility, etc.)
    |> Ecto.Multi.insert(:post,
      Post.changeset(%Post{}, attrs)
      |> Ecto.Changeset.put_change(:user_id, user.id)
    )

    # 2. Extract and Associate Hashtags
    |> Ecto.Multi.run(:hashtags, fn _repo, %{post: post} ->
      tags = parse_and_upsert_hashtags(post.content || "")

      post
      |> Repo.preload(:hashtags)
      |> Post.changeset(%{}) # Empty changeset for put_assoc
      |> Ecto.Changeset.put_assoc(:hashtags, tags)
      |> Repo.update()
    end)

    # 3. Handle Mentions & Reply Notifications
    |> Ecto.Multi.run(:notifications, fn _repo, %{media_upload: post} ->
      # A. Extract @mentions
      mentioned_users = extract_mentioned_users(post) #extract_and_notify_mentions(post)

      # B. Notify Parent (if it's a reply) (#Threading & Engagement)
      # Send Notification (Mentions)
      send_mention_notifications(post, mentioned_users)
       # Send Notification (Replies)
      notify_parent_author(post)

      # C. CRITICAL: Update the post's JSONB 'mentions' field for the React UI
      # Save those mentions back into the Post record
      # This prevents your frontend from having to re-parse the @username strings every time a post renders
      post
      |> Ecto.Changeset.change(mentions: Enum.map(mentioned_users, & %{id: &1.id, username: &1.username}))
      |> Repo.update()
    end)

    # 4. Attach Media (Waffle needs the Post ID for the folder path)
    # (Waffle.Ecto moves the file to /uploads/posts/[ID]/...)
    |> Ecto.Multi.run(:media_upload, fn _repo, %{post: post} ->
      if attrs["media"] do
        post
        |> Post.changeset(%{media: attrs["media"]}) # Waffle.Ecto handles the file move
        |> Repo.update()
      else
        {:ok, post}
      end
    end)

    # 5. Handle Lifecycle (Broadcasting & Background Video Tasks)
    # Lifecycle (Voice Alert + Video Processing)
    |> Ecto.Multi.run(:lifecycle, fn _repo, %{media_upload: post} ->
      # Broadcast if Voice (Your existing logic)
      if post.category == :voice, do: broadcast_voice(post) # <--- Trigger the real-time logic

      # Start Video processing if applicable
      if post.media_type == "video" do
        Task.start(fn -> process_video_background(post.id) end)
      end

      {:ok, post}
    end)
    #returns fo {:ok, %{lifecycle: post}}, it signifies that a group of database operations
    #wrapped in an Ecto.Multi was successful.
    |> Repo.transaction() # Returns {:ok, %{lifecycle: post}} or {:error, step, val, changes}
    |> broadcast_new_post() # <--- Live Feed feature
  end

  defp broadcast_new_post({:ok, %{post: post}} = result) do
    # Only broadcast if the post is public and published
    if post.visibility == "public" && post.status == :published do

      # A. THE HOME/PUBLIC FEED (Standard Live Feed)
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "feed:public",
        {:new_post, post}
      )

      # B. THE DISCOVERY/GEO FEED (Local, State, Country, World Tabs)
      # We broadcast to a single internal topic.
      # Your DiscoveryChannel will "catch" this and decide if it matches the user's tab.
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "discovery_updates",
        {:new_discovery_post, post}
      )
    end

    # Return the original result so the controller gets the data
    result
  end
  defp broadcast_new_post(error_result), do: error_result

  defp notify_parent_author(post) do
    # Find the parent post to get the author's ID
    if post.parent_id do
      parent = Repo.get(Post, post.parent_id)

      # Don't notify if I'm replying to myself
      if parent && parent.user_id != post.user_id do
        Kollective.Notifications.create_notification(%{
          user_id: parent.user_id,    # The person being replied to
          actor_id: post.user_id,     # The person who wrote the reply
          post_id: post.id,
          type: "reply"
        })
      end
    end

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
  end

  defp parse_and_upsert_hashtags(text) do
    # Regex to find words starting with #
    hashtags =
      Regex.scan(~r/#[[:alnum:]_]+/, text)
      |> List.flatten()
      |> Enum.map(&String.downcase(String.replace(&1, "#", "")))
      |> Enum.uniq()

    # Find existing tags or create new ones
    Enum.map(hashtags, fn name ->
      Repo.insert!(
        %Kollective.Hashtag{name: name},
        on_conflict: [set: [name: name]],
        conflict_target: :name
      )
    end)
  end

  defp extract_mentioned_users(post) do
    usernames =
      Regex.scan(~r/@[[:alnum:]_]+/, post.content || "")
      |> List.flatten()
      |> Enum.map(&String.replace(&1, "@", ""))
      |> Enum.uniq()

    Kollective.Accounts.list_users_by_usernames(usernames)
  end

  #Ensures you don't notify the author of their own mention and triggers the PubSub broadcast for each recipient
  defp send_mention_notifications(post, mentioned_users) do
    parent_author_id = get_parent_author_id(post)
    Enum.each(mentioned_users, fn recipient ->
      # Only notify if the recipient isn't the person who wrote the post

      #If a user replies to a post and mentions the parent author in that
      #same reply, they might get two notifications (one for reply, one for mention).
      #To fix this, added the check "recipient.id != parent_author_id" below:
      if recipient.id != post.user_id && recipient.id != parent_author_id do
        # 1. Create the DB record
        {:ok, notification} = Kollective.Notifications.create_notification(%{
          user_id: recipient.id,
          actor_id: post.user_id,
          post_id: post.id,
          type: "mention"
        })

        # 2. Broadcast to the user's private channel for a React "Toast"
        # This matches the pattern we used for Replies
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "user_notifications:#{recipient.id}",
          {:new_notification, notification}
        )
      end
    end)
  end

  #Threading & Engagement (logic to Notify the Parent Author when someone replies to their post)
  # Logic to notify the original author when someone replies to their post. Since your schema has
  # parent_id and in_reply_to_id, we can easily find the target user.
  #1. It checks if the post is a reply and ensures we don't notify the user of their own actions
  defp notify_parent_author(post) do
    # Find the parent post to get the author's ID
    if post.parent_id do
      parent = Repo.get(Post, post.parent_id)

      # Don't notify if I'm replying to myself
      if parent && parent.user_id != post.user_id do
        Kollective.Notifications.create_notification(%{
          user_id: parent.user_id,    # The person being replied to
          actor_id: post.user_id,     # The person who wrote the reply
          post_id: post.id,
          type: "reply"
        })
      end
    end
  end

  def create_post(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:post, Post.changeset(%Post{user_id: user.id}, attrs))
    # ...TODO merge with one above  (media, hashtags, mentions logic) ...
    |> Repo.transaction()
    |> broadcast_new_post() # <--- This handles the optional coordination
  end

  def create_post(user, attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:user, user) # Link the post to the author
    |> Repo.insert()
  end


  def create_post(user, attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> validate_and_fix_targeting(user)
    |> Repo.insert()
  end

  defp validate_and_fix_targeting(changeset, user) do
    organization_id = get_field(changeset, :organization_id)
    case user.type do
      :regular ->
        # REGULAR USER: Can choose :target_scope (Local/State/Country)
        # but is FORCED to their own home districts as the origin.
        changeset
        |> put_change(:origin_country, user.country)
        |> put_change(:origin_state, user.state)
        |> put_change(:origin_city_id, user.city_id)
        |> put_change(:origin_federal_district, user.federal_district)
        |> put_change(:origin_state_senate_district, user.state_senate_district)
        |> put_change(:origin_state_district, user.state_district)

      type when type in [:scholar, :journalist] or not is_nil(organization_id) ->
        # SCHOLAR/JOURNALIST: Can choose both :target_scope
        # OR posting on behalf of an Organization
        # AND a custom :origin district/state from the React UI.
        # We only set defaults if the UI left them blank.
        changeset
        |> default_value(:origin_country, user.country)
        |> default_value(:origin_state, user.state)
    end
  end

  #2. Broadcasting New Posts (lib/kollective/posts.ex)
  # Update your post creation logic to broadcast the new post to the relevant "topic".
  # Because a post can appear in multiple tabs for different people, we broadcast to specific
  # geographic strings.
  def create_post(user, attrs) do
    Repo.transaction(fn ->
      case %Post{} |> Post.changeset(attrs) |> Repo.insert() do
        {:ok, post} ->
          broadcast_new_post(post)
          {:ok, post}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp broadcast_new_post(post) do
    # 1. Broadcast to the Local tab of everyone in this specific anchor
    # Topic example: "discovery:local:TX:federal_12"
    topic = "discovery:local:#{post.origin_state}:#{post.origin_federal_district}"
    KollectiveWeb.Endpoint.broadcast(topic, "new_post", %{post: post})

    # 2. Broadcast to the State tab of everyone in the same state
    if post.target_scope in [:state, :country, :world] do
      state_topic = "discovery:state:#{post.origin_state}"
      KollectiveWeb.Endpoint.broadcast(state_topic, "new_post", %{post: post})
    end
  end

  def create_post(user, attrs) do
    content = attrs["content"]

    if contains_shadow_banned_words?(content) do
      # Set status to 'pending' instead of 'public'
      attrs = Map.put(attrs, "status", "pending")
      save_post(user, attrs)
    else
      save_post(user, attrs)
    end
  end

  defp contains_shadow_banned_words?(content) do
    # Fetch keywords from DB/Cache and check against content
    keywords = Kollective.Moderation.Moderations.list_restricted_keywords()
    Enum.any?(keywords, fn k -> String.contains?(content, k.word) end)
  end

  # Since Elixir is functional, you should pipe your post attributes
  # through a "scrubber" before they hit the database.
  def create_post(user, attrs) do
    content = Map.get(attrs, "content", "")
    # 1. Check if content contains any banned words
    status =
      if Kollective.Moderation.Moderations.contains_banned_word?(content) do
        "pending"
      else
        "published"
      end

    # 2. Inject the status into the attributes
    attrs = Map.put(attrs, "status", status)

    # 3. Proceed with standard Ecto insert
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  # shadow-ban for aggressive spammers
  def create_post(user, attrs) do
    content = Map.get(attrs, "content", "")

    # Check 1: Is the user globally shadow-banned?
    # Check 2: Does the post contain restricted keywords?
    is_restricted =
      user.is_shadow_banned || Kollective.Moderation.contains_banned_word?(content)

    status = if is_restricted, do: :pending, else: :published

    attrs = Map.put(attrs, "status", status)

    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

def create_post(user, attrs) do
  Repo.transaction(fn ->
    # 1. Save the post
    {:ok, post} =
      %Post{user_id: user.id}
      |> Post.changeset(attrs)
      |> Repo.insert()

    # 2. Extract usernames (e.g., @alice, @bob)
    usernames =
      Regex.scan(~r/@([a-zA-Z0-9_]+)/, post.content)
      |> Enum.map(fn [_, username] -> username end)
      |> Enum.uniq()

    # 3. Find mentioned users and notify them
    from(u in User, where: u.username in ^usernames)
    |> Repo.all()
    |> Enum.each(fn mentioned_user ->
      Kollective.Notifications.send_notification(mentioned_user, "#{user.username} mentioned you!")
    end)

    post
  end)
end

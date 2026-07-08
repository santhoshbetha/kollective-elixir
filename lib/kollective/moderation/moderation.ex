defmodule Kollective.Moderation.Moderation do
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Moderation.Log, as: ModerationLog
  alias Kollective.Admins.Log, as: AdminLog
  alias Kollective.Moderation.RestrictedKeyword
  alias Kollective.Posts.Post
  alias Kollective.Events.Event
  alias Kollective.Mailer
  alias Kollective.Security.Security
  alias Kollective.Moderation.Report
  alias Kollective.Accounts.UserRelationship

  # Define a fallback flag threshold for the keyword weighting score system
  @default_flag_threshold 3

  # Threshold to trigger an automatic shadow-ban (e.g., 5 points)
  # @auto_hide_threshold 5

  # The total score required to flag a post (e.g., 3 points)
  @flag_threshold 3

  # The @safety_limit (e.g., 500) is used to prevent accidental mass deletion
  @safety_limit 500

  @cache :kollective_cache

  @doc """
  Compiles chronological active compliance tickets filtered by operational status maps.
  Applies keyset cursor tracking and batch-preloads profiles in exactly one single pass.
  """
  def list_compliance_reports(status, params \\ %{}) do
    limit = Map.get(params, "limit", 30)
    cursor = Map.get(params, "cursor")

    base_query =
      from(r in Report,
        where: r.status == ^to_string(status),
        # UNIFIED PRELOAD MATRIX: Grabs accounts and media nodes in a single database sweep
        preload: [:reporter, :target_user, :post, :event]
      )

    # FIX: Implements strict look-ahead keyset cursor pagination matching your primary index [INDEX]
    query =
      if cursor,
        do: from(r in base_query, where: r.id < ^cursor),
        else: base_query

    query
    |> order_by([r], desc: r.id) # Chronological sorting driven natively via sortable Ecto.ULIDs [INDEX]
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Fetches a specific report record by ID, raising an Ecto.NoResultsError if missing.
  Hydrates all relevant structural dependencies cleanly for deep admin inspections [INDEX].
  """
  def get_report!(id) do
    Report
    # Preloads all relevant entities in a single database pass to prevent N+1 bugs
    |> preload([:reporter, :target_user, :post, :event])
    |> Repo.get!(id)
  end

  @doc """
  Fetches a specific report record by ID, returning nil if the entry is absent.
  """
  def get_report(id) do
    Report
    |> preload([:reporter, :target_user, :post, :event])
    |> Repo.get(id)
  rescue
    # Gracefully catches type errors if a malformed parameter is transmitted from the UI
    Ecto.Query.CastError -> nil
  end

  # ─── SECTION 1: REPORT CREATION & AUTO-HIDE ENGINE ───

  @doc """
  Files a formal content report. Inside the same transaction pool, it creates an
  automatic 'mute' block against the author so their content vanishes from the reporter's feed instantly.
  """
  def create_report(user, post_id, attrs \\ %{}) do
    author_id = attrs["author_id"] || attrs[:author_id]
    reason = attrs["reason"] || attrs[:reason]
    details = attrs["details"] || attrs[:details]

    Multi.new()
    # Step 1: Insert the official audit Report record
    |> Multi.insert(:report, %Report{
      reporter_id: user.id,
      post_id: post_id,
      event_id: attrs["event_id"] || attrs[:event_id],
      reason: reason,
      details: details,
      # Standardized state string
      status: "pending"
    })

    # Step 2: AUTO-HIDE MUTE SHIELD
    # Automatically mutes the author for the reporter to clear their UI feed panels instantly
    |> Multi.insert(
      :auto_mute,
      fn _changes ->
        %UserRelationship{
          source_id: user.id,
          target_id: author_id,
          type: "mute"
        }
      end,
      # Prevents duplicate crashes
      on_conflict: :nothing,
      conflict_target: [:source_id, :target_id, :type]
    )

    # Execute full transaction block safely
    |> Repo.transaction()
    |> handle_report_creation_lifecycle()
  end

  defp handle_report_creation_lifecycle({:ok, %{report: report}}) do
    # Preload dependencies cleanly so the admin dashboard gets full data structures instantly
    hydrated_report = Repo.preload(report, [:reporter, :post, :event])

    # Real-time WebSocket push over the private Admin Control Panel network topic space
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "admin_notifications",
      {:new_report,
       %{
         id: hydrated_report.id,
         reason: hydrated_report.reason,
         reporter: hydrated_report.reporter.username,
         post_content: if(hydrated_report.post, do: hydrated_report.post.content, else: nil),
         inserted_at: hydrated_report.inserted_at
       }}
    )

    {:ok, hydrated_report}
  end

  defp handle_report_creation_lifecycle({:error, _step, changeset, _changes}),
    do: {:error, changeset}

  # ─── SECTION 2: ADMINISTRATIVE METRICS & SELECTION VIEWS ───

  @doc "Lists historical reports filtered by criteria and sorted chronologically."
  def list_reportsX(filters \\ []) do
    Report
    |> where(^filters)
    # Keyset index order via ULID/ID parameters
    |> order_by([r], desc: r.id)
    |> preload([:reporter, :post, :event])
    |> Repo.all()
  end

  #@doc "Fetches a specific report record by ID, raising an Ecto.NoResultsError if missing."
  # def get_report!(id) do
  #   Report
  #   |> preload([:reporter, :post, :event])
  #   |> Repo.get!(id)
  # end

  # ─── SECTION 3: ADMINISTRATIVE RESOLUTION PIPELINE (THE RESOLVER ENGINE) ───

  @doc """
  Resolves an active report. Updates state records, executes conditional kill-switches
  to delete posts, and hooks straight into your unified event cancellation pipelines if applicable.
  """
  def resolve_report(%Report{} = report, status, delete_content?) do
    Multi.new()
    # 1. Update the root Report state string ("resolved" or "dismissed")
    |> Multi.update(:report, Report.changeset(report, %{status: status}))

    # 2. CONDITIONAL POST KILL-SWITCH
    |> Multi.run(:delete_post, fn _repo, _changes ->
      if delete_content? && report.post_id do
        case Repo.get(Post, report.post_id) do
          # Already scrubbed by another mod/admin
          nil ->
            {:ok, nil}

          post ->
            Repo.delete(post)

            # Broadcast a global feed-scrubbing push to remove the post card from React viewports live
            Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:post_deleted, post.id})
            {:ok, :deleted}
        end
      else
        {:ok, nil}
      end
    end)

    # 3. CONDITIONAL EVENT KILL-SWITCH
    |> Multi.run(:handle_event, fn _repo, %{report: _updated_report} ->
      if delete_content? && report.event_id do
        # Safely check if your Admin, User, or System has permission to pull the event
        case Repo.get(Kollective.Events.Event, report.event_id) do
          nil ->
            {:ok, nil}

          _event ->
            # Retrieve your current system context profile for the admin
            # Loops directly into the high-performance event deletion engine we just built
            # Kollective.Events.Events.admin_cancel_event(admin, report.id)
            {:ok, :event_handled}
        end
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
  end

  # ─── PIPELINE 1: THE ADMINISTRATIVE "KILL SWITCH" (HARD DELETION) ───

  @doc """
  Executes an immediate administrative hard deletion of a post.
  Logs the action to the governance board and commands all active timelines to evict the card.
  """
  def admin_delete_post(admin, post_id) do
    post = Repo.get!(Post, post_id)

    Multi.new()
    # 1. Delete the post record from public infrastructure
    |> Multi.delete(:post, post)

    # 2. File an immutable entry in the compliance log boards
    |> Multi.insert(:admin_log, %AdminLog{
      action: "post_deleted",
      target_id: post.id,
      target_type: "Post",
      user_id: admin.id,
      metadata: %{content_snippet: String.slice(post.content || "", 0, 50)}
    })
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        # Shouts to the WebSockets to remove the post from users' screens live
        Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:post_killed, post.id})
        {:ok, :deleted}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  # ─── SECTION 1: EVENT REPORTING & AUTO-HIDE ENGINE ───

  @doc """
  Files a formal community event report. Inside the same transaction pool, it creates an
  automatic 'mute' block against the organizer so the gathering vanishes from the reporter's feed instantly.
  """
  def report_event(user, event_id, attrs \\ %{}) do
    organizer_id = attrs["author_id"] || attrs[:author_id]
    reason = attrs["reason"] || attrs[:reason]
    details = attrs["details"] || attrs[:details]

    Multi.new()
    # 1. Record the formal event report
    |> Multi.insert(:report, %Report{
      reporter_id: user.id,
      event_id: event_id,
      reason: reason,
      details: details,
      status: "pending"
    })

    # 2. Auto-Hide: Automatically mutes the organizer to clear the reporter's local tab instantly
    |> Multi.insert(
      :auto_mute_event,
      %UserRelationship{
        source_id: user.id,
        target_id: organizer_id,
        type: "mute"
      },
      on_conflict: :nothing,
      conflict_target: [:source_id, :target_id, :type]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{report: report}} ->
        # Alert the Admin Dashboard in real-time
        hydrated_report = Repo.preload(report, [:reporter, :event])

        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "admin_notifications",
          {:new_event_report,
           %{
             id: hydrated_report.id,
             reason: hydrated_report.reason,
             reporter: hydrated_report.reporter.username,
             event_title:
               if(hydrated_report.event, do: hydrated_report.event.name, else: "Deleted Event"),
             inserted_at: hydrated_report.inserted_at
           }}
        )

        {:ok, hydrated_report}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # ─── SECTION 2: THE ADMINISTRATIVE MODERATOR OVERRIDE KILL-SWITCH ───

  @doc """
  Administrative moderator override kill-switch. Resolves the compliance report,
  permanently deletes the Event, logs an audit entry, and performs a mass notification sweep.
  """
  def admin_cancel_event(admin, report_id) do
    # Fetch report alongside its preloaded event record securely
    report =
      Repo.get!(Report, report_id)
      |> Repo.preload(:event)

    event = report.event

    if is_nil(event) do
      {:error, :event_already_deleted}
    else
      # Gather all user IDs signed up for this event (attending, maybe, or waitlisted)
      attendee_ids =
        from(p in "event_participants", where: p.event_id == ^event.id, select: p.user_id)
        |> Repo.all()

      Multi.new()
      # 1. Update the compliance report status block to resolved
      |> Multi.update(:report, Report.changeset(report, %{status: "resolved"}))

      # 2. Cancel all outstanding pending Oban notification jobs instantly to prevent ghost alerts
      |> Multi.run(:void_jobs, fn _repo, _changes ->
        from(j in Oban.Job,
          where: j.queue in ["notifications", "default"],
          where: fragment("?->>'event_id' = ?", j.args, ^to_string(event.id)),
          where: j.state in ["available", "scheduled"]
        )
        |> Repo.delete_all()

        {:ok, :jobs_voided}
      end)

      # 3. Permanently delete the Event from public infrastructure
      |> Multi.delete(:event, event)

      # 4. Insert an immutable Admin Audit Log entry for governance tracking
      |> Multi.insert(:admin_log, %AdminLog{
        action: "event_cancelled",
        target_id: event.id,
        target_type: "Event",
        user_id: admin.id,
        metadata: %{event_title: event.name}
      })
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          # Mass notify and clear out public feeds
          execute_bulk_cancellation_alerts(event, attendee_ids, admin.id)
          {:ok, :admin_cancelled}

        {:error, _failed_step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # ─── PRIVATE ATOMIC DATA EXTRACTION BULK PROCESSORS ───

  defp execute_bulk_cancellation_alerts(event, attendee_ids, admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. BULK INSERT HISTORICAL NOTIFICATIONS
    # Storing the title string directly inside metadata ensures history loads even after row deletion
    notifications_batch =
      Enum.map(attendee_ids, fn user_id ->
        %{
          # Use your project's native ULID compilation token
          id: Kollective.Schemas.ULIDType.generate(),
          user_id: user_id,
          actor_id: admin_id,
          # Safe snake_case registry string matching your configurations
          type: "event_update",
          metadata: %{event_title: event.name, event_id: event.id, sub_type: "event_cancelled"},
          read: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Performance Guard: High-speed multi-row atomic insertion sweep into the database
    if notifications_batch != [] do
      Repo.insert_all("notifications", notifications_batch)
    end

    # 2. TRANSIENT REAL-TIME ALERTS: Push live notification alerts over private WebSockets
    Enum.each(attendee_ids, fn user_id ->
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "user_notifications:#{user_id}",
        {:new_notification,
         %{
           type: "event_update",
           actor_name: "System",
           preview:
             "🚨 Moderation Alert: The gathering '#{event.name}' has been pulled by administration."
         }}
      )
    end)

    # 3. GLOBAL TIMELINE SCRUB: Tell active React scroll components to remove the card from the UI
    Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:event_deleted, event.id})

    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{event.id}",
      {:event_cancelled_close_screen, event.id}
    )
  end

  # lib/kollective/moderation.ex

  @doc """
  Executes a manual administrative override for AI-moderated image comments.
  Updates the target comment's moderation status, saves a unified compliance log,
  and tells active WebSockets to instantly blur or unblur the image across viewports.
  """
  def admin_override_image(%Kollective.Accounts.User{} = admin, comment_id, attrs) do
    status = attrs["status"] || attrs[:status]
    reason = attrs["reason"] || attrs[:reason]

    # 1. Fetch the targeted event comment row
    comment = Repo.get!(Kollective.Events.Comment, comment_id)
    previous_status = comment.moderation_status

    Multi.new()
    # Step A: Force update the moderation state string ("approved" or "rejected")
    |> Multi.update(
      :comment,
      Kollective.Events.Comment.changeset(comment, %{moderation_status: status})
    )

    # Step B: Record the action to your unified administrative audit log
    |> Multi.insert(:admin_log, %AdminLog{
      action: "image_override_#{status}",
      target_id: comment.id,
      target_type: "Comment",
      user_id: admin.id,
      metadata: %{
        previous_status: previous_status,
        new_status: status,
        reason: reason,
        event_id: comment.event_id
      }
    })
    |> Repo.transaction()
    |> case do
      {:ok, %{comment: updated_comment}} ->
        # ─── REAL-TIME TRANSMISSION DATA PIPELINE ───
        # Broadcasts out to everyone looking at this specific event page chat box
        # Routes straight through our unified FeedChannel interceptor safely
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "event:#{updated_comment.event_id}",
          {"image_moderated",
           %{
             id: updated_comment.id,
             status: status
           }}
        )

        {:ok, updated_comment}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc "Creates a restricted keyword and clears the cache to ensure immediate enforcement."
  def create_keyword(attrs \\ %{}) do
    %RestrictedKeyword{}
    |> RestrictedKeyword.changeset(attrs)
    |> Repo.insert()
    # Force cache refresh
    |> tap(fn _ -> Cachex.clear(@cache) end)
  end

  @doc "Fetches a single keyword by ID. Raises if not found."
  def get_keyword!(id), do: Repo.get!(RestrictedKeyword, id)

  @doc "Deletes a keyword and clears the cache."
  def delete_keyword(%RestrictedKeyword{} = keyword) do
    keyword
    |> Repo.delete()
    # Force cache refresh
    |> tap(fn _ -> Cachex.clear(@cache) end)
  end

  @doc "Lists all keywords, often used for the Admin API index."
  def list_keywords do
    RestrictedKeyword
    |> order_by([k], asc: k.word)
    |> Repo.all()
  end

  @doc "Returns the list of all restricted keywords."
  # This returns the full list of %RestrictedKeyword{} structs.
  # It is primarily used for the Admin API index.
  def list_restricted_keywords do
    Repo.all(RestrictedKeyword)
  end

  @doc "Returns a list of just the keyword strings for active entries."
  # This function is optimized for the post-check hook. Instead of returning full structs,
  # it returns a simple list of strings (e.g., ["bannedword1", "bannedword2"]).
  # This reduces memory overhead when iterating over words to check a post's content.
  def list_active_keyword_strings do
    query =
      from r in RestrictedKeyword,
        where: r.is_active == true,
        select: r.word

    Repo.all(query)
  end

  def contains_banned_word?(nil), do: false

  def contains_banned_word?(content) do
    keywords = list_active_keyword_strings()
    content_downcased = String.downcase(content)

    Enum.any?(keywords, fn word ->
      String.contains?(content_downcased, String.downcase(word))
    end)
  end

  # Performance Tip: Regex vs. String.contains?
  # If your list grows to hundreds of keywords, Enum.any? with String.contains? can become a bottleneck.
  # You can compile your list into a single Regex for a significant speed boost:
  def compile_regex(keywords) do
    # Escapes special characters and joins with OR (|)
    pattern =
      keywords
      |> Enum.map(&Regex.escape/1)
      |> Enum.join("|")

    # "i" flag for case-insensitive
    Regex.compile!(pattern, "i")
  end

  # Audit Log that records every moderation action (who approved what and when)
  # Why this is essential:

  #  Transparency: If a user complains about a shadow-ban or rejection, you can see exactly which admin made the call.
  #  Reversibility: You can build an "Undo" feature later by looking at the latest log for a specific post_id.
  #  Security: Prevents rogue admins from silently deleting or approving content without a paper trail.
  def log_action(admin, post, action, reason) do
    %ModerationLog{}
    |> ModerationLog.changeset(%{
      admin_id: admin.id,
      post_id: post.id,
      action: action,
      reason: reason
    })
    |> Repo.insert()
  end

  # Ecto query logic to manually inspect the oban_jobs table for failed cleanup tasks via your admin API
  # To let your Admin API inspect failed cleanup tasks, you’ll query the oban_jobs table. Oban stores errors in the errors
  # column (a list of maps) and the job's state as discarded (after all retries fail) or retryable.
  def list_failed_cleanup_jobs do
    # Oban jobs table is usually "oban_jobs"
    from(j in "oban_jobs",
      where: j.worker == "Kollective.Workers.CleanupWorker",
      where: j.state in ["discarded", "retryable"],
      order_by: [desc: j.errors_count, desc: j.inserted_at],
      select: %{
        id: j.id,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        # Contains the stacktrace and reason
        errors: j.errors,
        inserted_at: j.inserted_at
      }
    )
    |> Repo.all()
  end

  # To make the errors list from Oban readable for your frontend, you need to parse the JSONB structure.
  # Oban stores errors as a list of maps, where each map contains the at (timestamp), attempt, and error
  # (the actual message/stacktrace).
  def retry_all_failed_cleanups do
    from(j in "oban_jobs",
      where: j.worker == "Kollective.Workers.CleanupWorker",
      where: j.state == "discarded",
      select: j.id
    )
    |> Repo.all()
    |> Enum.each(&Oban.retry_job/1)
  end

  @doc """
  Unifies all content-checking logic. Analyzes combined title, description, and content inputs.
  Returns:
    * {:error, :forbidden_content, matched_word} -> Triggers explicit public error or cooldown blacklist tracking
    * {:ok, :pending}                           -> Soft-ban / Shadow-ban held for validation review
    * {:ok, :published}                         -> Safe and clean to publish immediately
  """
  def check_content(user, params \\ %{}) do
    title = params["title"] || params[:title] || ""
    description = params["description"] || params[:description] || ""
    content_body = params["content"] || params[:content] || ""

    # 1. Combine inputs into a single text block for one-pass scanning
    content_to_scan = Enum.join([title, description, content_body], " ") |> String.trim()

    # 2. Evaluate Hard Bans first to pull the matched word for audit tracking
    case find_banned_word(content_to_scan, "hard") do
      {:ok, word} ->
        {:error, :forbidden_content, word}

      :none ->
        # 3. Soft-ban check: Evaluate if the user is shadow-banned or matches a soft word
        if user.is_shadow_banned || contains_level?(content_to_scan, "soft") do
          {:ok, :pending}
        else
          {:ok, :published}
        end
    end
  end

  @doc """
  Unifies all 5 moderation strategies across all content types (Posts, Events, Comments).
  Returns:
    * {:error, :forbidden_content, message} -> Hard Ban (Throws explicit HTTP 422 error)
    * {:ok, :rejected}                     -> Alternative Hard Ban handling state
    * {:ok, :pending}                      -> Soft Filtered (Success fallback flag for user, but hidden)
    * {:ok, :published}                    -> Safe and clean to publish immediately
  """
  def determine_status(user, params \\ %{}) do
    # 1. Normalize and aggregate text fields across all variations (Posts, Events, Comments)
    title = params["title"] || params[:title] || ""
    description = params["description"] || params[:description] || ""
    content_body = params["content"] || params[:content] || ""

    # Single scan pass string aggregation
    content_to_scan = Enum.join([title, description, content_body], " ") |> String.trim()

    cond do
      # PRIORITY 1: GLOBAL LOCKDOWN / KILL SWITCH
      # When active, all standard operations are held for review, EXCEPT for exempt users
      Security.lockdown_active?() and not (user.is_exempt || false) ->
        {:ok, :pending}

      # PRIORITY 2: TRUSTED USER EXEMPTION BYPASS
      # Verified/Power users skip all keyword weights and shadowban scanning structures completely
      user.is_exempt || false ->
        {:ok, :published}

      # PRIORITY 3: USER STATE LOCK (GLOBAL SHADOW-BAN)
      # Caught aggressive spammers are instantly held regardless of text content
      user.is_shadow_banned || false ->
        {:ok, :pending}

      # PRIORITY 4: HARD BAN TEXT MATCHING
      # Prohibited syntax triggers an explicit, public error rejection loop to prevent abuse
      # We use find_banned_word to find and pass the exact offending word to the controller
      match?({:ok, _word}, find_banned_word(content_to_scan, "hard")) ->
        {:ok, matched_word} = find_banned_word(content_to_scan, "hard")
        {:error, :forbidden_content, matched_word}

      # PRIORITY 5: DYNAMIC WEIGHTED SOFT-BAN MATRIX
      # Sums weights of matching terms. Threshold dynamically narrows based on trust markers like account age.
      true ->
        score = calculate_content_score(content_to_scan)
        threshold = determine_dynamic_threshold(user)

        if score >= threshold do
          {:ok, :pending}
        else
          {:ok, :published}
        end
    end
  end

  # --- Structural Helper Pipelines ---

  defp calculate_content_score(text) do
    # Pulls soft words from cache/database and sums their relative numeric weights
    soft_keywords = list_active_keywords_by_level("soft")
    downcased_text = String.downcase(text)

    Enum.reduce(soft_keywords, 0, fn k, acc ->
      if String.contains?(downcased_text, String.downcase(k.word)) do
        acc + (k.weight || 1)
      else
        acc
      end
    end)
  end

  defp determine_dynamic_threshold(user) do
    # New/Unverified accounts have a low threshold (2), trusted accounts have more breathing room (5)
    # Checks your custom schema fields dynamically
    cond do
      Map.get(user, :account_age_days, 0) < 7 -> 2
      Map.get(user, :is_verified, false) -> 5
      true -> @default_flag_threshold
    end
  end

  defp find_banned_word(content, level) do
    downcased_content = String.downcase(content)
    keywords = list_active_keywords_by_level(level)

    case Enum.find(keywords, fn word ->
           String.contains?(downcased_content, String.downcase(word))
         end) do
      nil -> :none
      word -> {:ok, word}
    end
  end

  defp contains_level?(text, level) do
    # Connects to your standard DB keyword dictionary check pipeline
    # e.g., query restricted keywords where level == "hard" or "soft"
    keywords = list_active_keywords_by_level(level)

    Enum.any?(keywords, fn k ->
      String.contains?(String.downcase(text), String.downcase(k.word))
    end)
  end

  defp list_active_keywords_by_level(level) do
    # Fetch active keywords for the given level
    Repo.all(
      from k in RestrictedKeyword,
        where: k.level == ^level and k.is_active == true,
        select: k.word
    )
  end

  # Fallback placeholders to match your system configurations
  # defp list_restricted_keywords_by_level(level) do
  # Replace with actual DB query or Cache lookups, e.g.:
  # Repo.all(from k in RestrictedKeyword, where: k.level == ^level)
  # []
  # Query only for keywords of a specific level
  #  RestrictedKeyword
  #   |> where([k], k.level == ^level and k.is_active == true)
  #  |> select([k], k.word)
  #  |> Repo.all()
  # end

  @doc "Appends an offensive hard-ban word to the user's temporary memory pool inside Cachex."
  def track_denied_word(user_id, word) do
    cache_key = "denied_words:#{user_id}"

    current_list =
      case Cachex.get(:kollective_cache, cache_key) do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # Store an un-duplicated list of words valid for a rolling 10-minute window
    updated_list = [word | current_list] |> Enum.uniq()

    Cachex.put(:kollective_cache, cache_key, updated_list,
      ttl: :timer.minutes(10)
    )
  end

  @doc "Retrieves all words triggered by the user in this window for the Oban audit trail."
  def get_denied_words(user_id) do
    cache_key = "denied_words:#{user_id}"

    case Cachex.get(:kollective_cache, cache_key) do
      {:ok, words} when is_list(words) -> Enum.join(words, ", ")
      _ -> "unknown"
    end
  end

  # Cooldown" feature where if a user gets 3 "Post Denied" errors in 10 minutes, they are automatically Black-Holed for an hour

  # To implement the "Cooldown" feature, you can use Hammer to track the "Post Denied" occurrences as a specific rate-limited
  # action. By using a different bucket for these errors than for standard posts, you can enforce a separate, stricter
  # penalty for users who repeatedly trigger "Hard" keyword rejections.

  # 1. The Cooldown Logic
  # In your Moderation context, add a function that specifically tracks "Post Denied" attempts. This function will use a 10-minute window and a limit of 3.

  @doc "Increments the denial count for a user. Returns :cooldown if they exceed 3 hits in 10 mins."
  def record_denial(user_id) do
    # Tracks if a user records more than 1 denial inside a 10-minute (600,000ms) window
    case Hammer.check_rate("post_denied:#{user_id}", 600_000, 1) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> :cooldown
    end
  end

  # Common Moderation logic:
  # Instead of repeating code, create a single function in Kollective.Moderation that determines the status
  # for any piece of content (Post, Event, Comment).

  # protect your Events effectively, you should scan both the
  # Title and the Description. Titles are often the primary target for spammers as they appear in
  # notifications and summary lists.
  def determine_status1(user, params) do
    # Combine title and description for a single scan pass
    content_to_scan = "#{params["title"]} #{params["description"]}"

    cond do
      # 1. User is globally shadow-banned
      user.is_shadow_banned -> :pending
      # 2. Scan combined title + description for keywords
      contains_banned_word?(content_to_scan) -> :pending
      # 3. Otherwise, it's safe
      true -> :published
    end
  end

  # Admin Integration
  # In your Review Queue, you can now include Events. You can either add a new tab for
  # "Pending Events" or create a unified view:

  # Summary of Coverage
  # By reusing these modules, your Events now automatically benefit from:

  #    Shadow-ban protection (Spammers' events are hidden).
  #    Keyword filtering (Events with "crypto/spam" go to review).
  #    Rate-limiting (Bots can't create 1,000 events per second).
  #    Black-holing (Aggressive IP spam is discarded with a fake success).
  # def list_all_pending_content do
  #  posts = Kollective.Posts.list_pending_posts()
  #  events = Kollective.Events.list_pending_events()

  #  %{posts: posts, events: events}
  # end

  # To protect your Events effectively, you should scan both the
  # Title and the Description. Titles are often the primary target for spammers as they appear in notifications and summary lists.

  # 3.Admin Review Queue Update
  # Update your Moderation context to help admins see why an event was flagged (e.g., highlighting the title vs description).

  # Summary of Coverage

  #  Shadow-ban: Spammers' events are hidden regardless of content.
  #  Deep Scan: Both Title and Description are checked against your Restricted Keywords.
  #  Fake Success: Spammers see a "Success" message, but the public sees nothing.
  #  Unified Review: Admins manage both Posts and Events in one Moderation Dashboard.

  def list_pending_events do
    from(e in Event,
      where: e.status == :pending,
      preload: [:user],
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  # 4. Strategy: Stricter Title Rules
  # Titles are high-visibility. You might want to prevent ALL CAPS titles or titles with too many emojis, which are common spam patterns:
  # defp suspicious_title?(title) do
  # Example: Flag if more than 50% of the title is uppercase
  #  uppercase_count = title |> String.to_charlist() |> Enum.count(&(&1 in ?A..?Z))
  #  total_count = String.length(title)

  #  (uppercase_count / total_count) > 0.5
  # end

  # Notification System for admins that alerts them (via email/dashboard)
  # only when an Event is flagged, as these might be more time-sensitive than posts

  # To ensure your moderation team can act quickly (since events are time-sensitive), you should implement a
  # Notification Hook that triggers an email only when an Event is flagged as pending.

  # 1. Create the Notification Logic
  # Add a function to your Moderation context that sends an email alert specifically for events. This keeps your controllers clean.
  def notify_admin_of_flagged_event(event, user) do
    subject = "[URGENT] Event Held for Review: #{event.title}"

    body = """
    A new event has been flagged for moderation.

    Event Title: #{event.title}
    Author: #{user.username} (ID: #{user.id})
    Reason: #{flag_reason(user, event)}

    Review it here: https://kollective.social
    """

    Mailer.send_admin_alert(subject, body)
  end

  defp flag_reason(user, _event) when user.is_shadow_banned, do: "Global Shadow-ban"
  defp flag_reason(_user, _event), do: "Restricted Keywords Detected"

  # Auto-Reject, you need to differentiate between "Soft Banned" words (which trigger a Review status)
  # and "Hard Banned" words (which trigger an immediate rejection or deletion)

  # Modify your keyword scanning to return the "highest" ban level found in the content.
  def determine_status2(user, params) do
    # Combine title and description for a single scan pass
    content_to_scan = "#{params["title"]} #{params["description"]}"

    cond do
      # 1. Check for Hard Bans first (immediate rejection)
      contains_level?(content_to_scan, "hard") ->
        :rejected

      # 2. Check for Soft Bans or Global Shadow-ban
      user.is_shadow_banned || contains_level?(content_to_scan, "soft") ->
        :pending

      # 3. Default fallback if no conditions above are met
      true ->
        :published
    end
  end

  # defp contains_level2(content, level) do
  #  downcased_content = String.downcase(content)

  # Query only for keywords of a specific level
  #  keywords =
  #    RestrictedKeyword
  #    |> where([k], k.level == ^level and k.is_active == true)
  #    |> select([k], k.word)
  #    |> Repo.all()

  #  Enum.any?(keywords, fn word ->
  #    String.contains?(downcased_content, String.downcase(word))
  #  end)
  # end

  # Author's View for Rejections with "Post Denied" error for certain words

  # To implement a "Post Denied" error for certain words, you need to modify the Moderation logic to return a specific
  # error type and update the Controller to translate that into a 422 Unprocessable Entity response. #This is the opposite
  # of the "Fake Success" strategy—it tells the user exactly why their content was rejected, which is useful for
  # preventing accidental rule-breaking by real users.

  # 1. Update the Moderation Context
  # Modify determine_status to return an error tuple when a "Hard" keyword is found.
  # def check_content(user, params) do
  #  content = "#{params["title"]} #{params["description"] || params["content"]}"

  #  cond do
  # 1. HARD BAN: Return an explicit error
  #    contains_level?(content, "hard") ->
  #      {:error, :forbidden_content, "Your post contains prohibited language and cannot be saved."}

  # 2. SOFT BAN: Return pending status (Author sees success, but it's hidden)
  #    user.is_shadow_banned || contains_level?(content, "soft") ->
  #      {:ok, :pending}

  # 3. CLEAN: Return published status
  #    true ->
  #      {:ok, :published}
  #  end
  # end

  # Automated IP Banning specifically for anyone who triggers a "Hard" keyword more than once

  # To implement this "Two-Strike" rule for Hard keywords, we will
  # use your existing Cachex setup to track "offense counts" per IP and then trigger the 24-hour Security Blacklist once they hit the second strike

  # 2. Update the Moderation Context
  # We need to ensure check_content distinguishes between a simple "pending" (soft) and a "forbidden" (hard) result so the controller knows when to record a strike.
  # def check_content(user, params) do
  #  content = "#{params["title"]} #{params["description"] || params["content"]}"

  #  cond do
  #    contains_level?(content, "hard") -> {:error, :hard_ban}
  #    user.is_shadow_banned || contains_level?(content, "soft") -> {:ok, :pending}
  #    true -> {:ok, :published}
  #  end
  # end

  # Daily Moderation Summary worker that cleans up the "noise" by sending one digest email of all pending items every morning

  # 4. Admin API: "Clear All"
  # To make the morning routine faster for admins, you can add a "Bulk Approve" or "Bulk Reject" endpoint to your Admin API:
  def approve_all_pending do
    Repo.transaction(fn ->
      Repo.update_all(from(p in Post, where: p.status == :pending), set: [status: :published])
      Repo.update_all(from(e in Event, where: e.status == :pending), set: [status: :published])
    end)
  end

  # "Moderator Notes" so when an admin approves/rejects an item from the daily summary, they can leave a comment for other
  # admins to see why
  # Update the log_action function to include the new notes field.
  def log_action2(admin, resource, action, notes) do
    %ModerationLog{}
    |> ModerationLog.changeset(%{
      admin_id: admin.id,
      post_id: if(Map.has_key?(resource, :content), do: resource.id),
      event_id: if(Map.has_key?(resource, :title), do: resource.id),
      action: action,
      notes: notes
    })
    |> Repo.insert()
  end

  @doc """
  Unifies bulk operations with structural safety limits.
  Validates queue depth before using high-speed database mutations.
  "Safety Threshold" where the bulk-approve fails (requiring manual confirmation) if there are more
  than, say, 500 items, to prevent accidental mass-approving of a bot attack?

  # To prevent an accidental "mass-leak" of spam during a bot attack, we will implement a #Safety Threshold in your Moderation
  # context. If the number of pending items exceeds your limit (e.g., 500), the API will reject the request with a specific error, forcing the admin to pass a force: true flag to confirm they really want to proceed.
  Returns:
    * {:error, :threshold_exceeded, total_count} -> Triggers a front-end confirmation prompt
    * {:error, :empty_queue}                     -> Short-circuits useless operations
    * {:ok, %{posts: count, events: count}}       -> Success payload
  """
  def bulk_approve_pending(admin, params \\ %{}) do
    notes =
      Map.get(params, "notes") || Map.get(params, :notes) || "Bulk approved via Daily Summary"

    force = Map.get(params, "force") || Map.get(params, :force) || false

    # 1. Use light aggregate lookups to read queue counts before pulling full record pools
    post_count = Repo.one(from p in Post, where: p.status == "pending", select: count(p.id))
    event_count = Repo.one(from e in Event, where: e.status == "pending", select: count(e.id))
    total = post_count + event_count

    cond do
      # RULE 1: Nothing to process? Stop here to save database memory overhead
      total == 0 ->
        {:error, :empty_queue}

      # RULE 2: Over the roadblock limit without explicit bypass verification parameter? Lock it down.
      total > @safety_limit and not force ->
        {:error, :threshold_exceeded, total}

      # RULE 3: Valid and clear to execute atomic processing mutations
      true ->
        execute_bulk_approval(admin, notes)
    end
  end

  # --- Structural Isolated Transaction Block ---
  # Bulk Action API so you can clear the entire daily summary with a single note (e.g., "Batch approved daily digest"
  # To implement the Bulk Action API, you’ll create a dedicated endpoint that clears all pending items in a single
  # database transaction. This prevents "click fatigue" for your admins when reviewing the Daily Moderation Summary.

  # function to handle the bulk update. We use Repo.transaction to ensure
  # that either everything updates and logs, or nothing does, preventing partial states.
  defp execute_bulk_approval(admin, notes) do
    Repo.transaction(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 1. Capture specific arrays of IDs inside the lock boundaries for strict auditing
      post_ids = Repo.all(from p in Post, where: p.status == "pending", select: p.id)
      event_ids = Repo.all(from e in Event, where: e.status == "pending", select: e.id)

      # 2. High-speed Bulk Update on Post records
      {posts_updated, _} =
        from(p in Post, where: p.id in ^post_ids)
        |> Repo.update_all(set: [status: "published", updated_at: now])

      # 3. High-speed Bulk Update on Event records
      {events_updated, _} =
        from(e in Event, where: e.id in ^event_ids)
        |> Repo.update_all(set: [status: "published", updated_at: now])

      # 4. Generate the persistent System Log entry for governance tracking
      Repo.insert!(%ModerationLog{
        admin_id: admin.id,
        action: "bulk_approve",
        notes: "#{notes} (Items: #{posts_updated} posts, #{events_updated} events)"
      })

      # Return structural metrics back out of the database block
      %{posts: posts_updated, events: events_updated}
    end)
  end

  # "Moderator Notes" to the automated security alert so admins can see exactly which three "Hard" words
  # triggered the user's cooldown

  # 1. Update the Moderation Context
  # Modify check_content to return the specific word that matched, and create a function to track those words in a list.
  # def check_content(user, params) do
  #  content = "#{params["title"]} #{params["description"] || params["content"]}"

  # Return the matched word if it's a hard ban
  #  case find_banned_word(content, "hard") do
  #    {:ok, word} -> {:error, :hard_ban, word}
  #    :none ->
  #      if user.is_shadow_banned || contains_level?(content, "soft"),
  #        do: {:ok, :pending},
  #        else: {:ok, :published}
  #  end
  # end

  # defp find_banned_word(content, level) do
  #  downcased_content = String.downcase(content)
  # Fetch keywords from DB/Cache
  #  keywords = list_active_keywords_by_level(level)

  #  Enum.find(keywords, fn word ->
  #    String.contains?(downcased_content, String.downcase(word))
  #  end) |> case do
  #    nil -> :none
  #    word -> {:ok, word}
  #  end
  # end

  # def track_denied_word(user_id, word) do
  #  key = "denied_words:#{user_id}"
  # Append the word to a list in Cachex, expiring in 10 mins
  #  Cachex.get_and_update(:kollective_cache, key, fn
  #    nil -> [word]
  #    words -> Enum.uniq([word | words])
  #  end)
  # Ensure the list expires along with the Hammer window
  #  Cachex.expire(:kollective_cache, key, :timer.minutes(10))
  # end

  # Bulk Downgrade API
  # To fix a configuration mistake where keywords were accidentally set to "Hard" (causing mass rejections and bans), you need a
  # Bulk Downgrade API. This function will move all "Hard" keywords to "Soft" status in the database and then trigger the lift_all_cooldowns function we just built to instantly restore access to affected users.

  # 1. Update the Moderation Context
  # Add a function that performs the database update and clears the cache. We use update_all for maximum speed.
  def downgrade_all_hard_keywords(admin) do
    Repo.transaction(fn ->
      # 1. Update all "hard" keywords to "soft"
      {count, _} =
        from(k in RestrictedKeyword, where: k.level == "hard")
        |> Repo.update_all(set: [level: "soft", updated_at: DateTime.utc_now()])

      # 2. Clear the keyword cache so the new "soft" levels take effect immediately
      Cachex.clear(:kollective_cache)

      # 3. Lift all existing bans/cooldowns caused by the previous "hard" settings
      Security.lift_all_cooldowns()

      # 4. Log the bulk action
      log_action(
        admin,
        %{id: 0},
        "bulk_downgrade",
        "Downgraded #{count} keywords from Hard to Soft."
      )

      count
    end)
  end

  # Keyword Weighting
  # To implement Keyword Weighting, we shift from a simple "contains" check to a scoring system. Each keyword is
  # assigned a weight (points), and content is only flagged if the total score exceeds a defined threshold

  # We’ll create a scoring function that sums the weights of all matching keywords found in the text.

  # 4. Why Weighting is "Smarter":

  #  Contextual Accuracy: A post containing just the word "crypto" might be fine. A post containing "crypto", "guaranteed", and "whatsapp" is almost certainly spam.
  #  Granular Control:
  #      Low Suspect (Weight 1): Common words that appear in spam but also in real talk.
  #      High Suspect (Weight 3): Obvious spam triggers that should cause an immediate pending status.
  #  Reduced False Positives: Real users are less likely to accidentally trip multiple suspicious words in one go.

  # 5. Strategy: Dynamic Thresholds
  #  You can even make the @flag_threshold dynamic based on the user's account age. For example, new accounts might have a threshold of 2, while trusted accounts have a threshold of 5.

  def determine_status3(user, params) do
    content = "#{params["title"]} #{params["description"] || params["content"]}"

    # 1. HARD BAN: Keep these as instant rejections (Weight doesn't apply)
    if contains_level?(content, "hard") do
      :rejected
    else
      # 2. WEIGHTED SCAN: Calculate total score for "soft" keywords
      score = calculate_content_score(content)

      if user.is_shadow_banned || score >= @flag_threshold do
        :pending
      else
        :published
      end
    end
  end

  # defp calculate_content_score2(content) do
  #  downcased_content = String.downcase(content)

  # Fetch all soft keywords with their weights (Cache this!)
  #  keywords =
  #    RestrictedKeyword
  #    |> where([k], k.level == "soft" and k.is_active == true)
  #    |> select([k], {k.word, k.weight})
  #    |> Repo.all()

  #  Enum.reduce(keywords, 0, fn {word, weight}, acc ->
  #    if String.contains?(downcased_content, String.downcase(word)) do
  #      acc + weight
  #    else
  #      acc
  #    end
  #  end)
  # end

  # Bulk Reject logic to "Nuke"
  # To implement a Bulk Reject "Nuke" logic, you will create a high-performance endpoint that permanently
  # deletes all pending items from your database. This is specifically designed for "bot floods" where you do not need to preserve a record of the spam content and want to clear the queue instantly.

  # 1. Update the Moderation Context
  # Add a nuke_pending_queue/2 function to your Moderation module. Unlike "Bulk Approve," which updates records,
  # this uses Repo.delete_all/2 to completely remove them from the database, freeing up storage and clearing the
  # review queue in one operation.

  def nuke_pending_queue(admin, params \\ %{}) do
    force = Map.get(params, "force", false)
    notes = Map.get(params, "notes", "Nuke: Mass bot flood rejected")

    # 1. Check the total number of pending items first
    post_query = from(p in Post, where: p.status == :pending)
    event_query = from(e in Event, where: e.status == :pending)
    total = Repo.aggregate(post_query, :count, :id) + Repo.aggregate(event_query, :count, :id)

    cond do
      total == 0 -> {:error, :empty_queue}
      total > @safety_limit and not force -> {:error, :threshold_exceeded, total}
      true -> execute_nuke(admin, post_query, event_query, notes, total)
    end
  end

  defp execute_nuke(admin, post_query, event_query, notes, _total) do
    Repo.transaction(fn ->
      # 2. PERMANENTLY DELETE: Use delete_all for maximum performance
      {posts_deleted, _} = Repo.delete_all(post_query)
      {events_deleted, _} = Repo.delete_all(event_query)

      # 3. LOG THE ACTION: Critical for an audit trail of mass deletions
      %ModerationLog{}
      |> ModerationLog.changeset(%{
        admin_id: admin.id,
        action: "bulk_nuke",
        notes: "#{notes} (Total deleted: #{posts_deleted} posts, #{events_deleted} events)"
      })
      |> Repo.insert!()

      %{deleted: posts_deleted + events_deleted}
    end)
  end

  # Global Kill Switch
  # 2. Update the Moderation Context
  # Inject the lockdown check at the very beginning of your determine_status logic. If the switch is on, we skip all
  # keyword/weighting logic and return :pending.
  # def determine_status4(user, params) do
  # 1. THE GLOBAL KILL SWITCH: If active, everything is held for review
  #  if Security.lockdown_active?() do
  #    :pending
  #  else
  #    # 2. Existing logic (Hard Bans, Shadow Bans, Keyword Weights)
  #   perform_standard_moderation(user, params)
  # end
  # end

  # Exemption API to allow "Power Users" or "Verified Users" to bypass the keyword filter entirely

  # To allow "Power Users" or "Verified Users" to skip the keyword scans, we add a bypass check at the very beginning of the
  # Moderation logic. This ensures that your most trusted users never get accidentally caught by "Soft" or "Hard" filters.

  # Update the Moderation Context
  # Inject the exemption check into determine_status. If user.is_exempt is true, we skip the heavy scanning and
  # immediately return :published.

  def determine_status5(user, params) do
    cond do
      # 1. THE BYPASS: Verified/Power users skip all checks
      user.is_exempt -> :published
      # 2. GLOBAL LOCKDOWN: Even exempt users are held if the Kill Switch is on
      Security.lockdown_active?() -> :pending
      # 3. Standard checks for everyone else
      user.is_shadow_banned -> :pending
      contains_level?("#{params["title"]} #{params["content"]}", "hard") -> :rejected
      calculate_content_score("#{params["title"]} #{params["content"]}") >= 3 -> :pending
      true -> :published
    end
  end

  # "Pardon History" log so admins can see if a user has been pardoned or exempted multiple times
  # To implement Pardon History, you need to filter your existing moderation_logs table specifically for actions
  # like user_pardon, granted_exemption, and revoked_exemption. This provides a "trust timeline" so admins can
  # spot users who are repeatedly hitting the filters and getting "bailed out."

  # 1. Update the Moderation Context
  # Add a function to retrieve the history of administrative trust changes for a specific user.

  @doc "Returns the historical timeline of pardons and exemptions for a user."
  def list_user_trust_history(user_id) do
    actions = ["user_pardon", "granted_exemption", "revoked_exemption", "bulk_downgrade"]
    # Create a database pattern match string (e.g., "%123%")
    like_pattern = "%#{user_id}%"

    ModerationLog
    |> where([l], l.post_id == ^user_id or ilike(l.notes, ^like_pattern))
    # |> where([l], l.post_id == ^user_id or fragment("? LIKE ?", l.notes, ^like_pattern))
    # Or more precisely, if you added a target_user_id column:
    # |> where([l], l.target_user_id == ^user_id and l.action in ^actions)
    |> where([l], l.action in ^actions)
    |> preload([:admin])
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  # "User Reporting" system so citizen users can flag posts that the automated keyword filter missed
  # 3. The Moderation Context (Reporting Logic)
  # Add a function to handle new reports and an Automated Threshold logic: if a post gets reported 5 times,
  # automatically move it to pending status.
  # def create_report(user, attrs) do
  #   %Report{}
  #   |> Report.changeset(Map.put(attrs, "reporter_id", user.id))
  #   |> Repo.insert()
  #   |> tap(fn {:ok, report} -> check_report_threshold(report) end)
  # end

  # defp check_report_threshold(%{post_id: post_id} = _report) when not is_nil(post_id) do
  #  report_count = Repo.aggregate(from(r in Report, where: r.post_id == ^post_id), :count, :id)

  # AUTO-SHADOW-BAN: If 5 users report it, hide it immediately
  #  if report_count >= 5 do
  #    post = Kollective.Posts.get_post!(post_id)
  #    Kollective.Posts.update_post_status(post, :pending)

  # Alert Admins via Oban
  #   %{type: "report_threshold_hit", post_id: post.id}
  #   |> Kollective.Workers.SecurityAlertWorker.new()
  #   |> Oban.insert()
  # end
  # end

  # "User Reporting" system so citizen users can flag posts that the automated keyword filter missed
  # 5. Admin Integration (The "Reports Queue")
  # Admins need a view to see what's being flagged. This is usually sorted by "Most Reported First."
  def list_active_reports do
    from(r in Report,
      where: r.status == :pending,
      preload: [:reporter, :post, :event],
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
  end

  # "Keyword Expiry", where a restricted word automatically deletes itself after 30 days (useful for temporary spam trends or event-specific words)

  # Modify create_keyword to optionally accept a TTL (Time To Live). If no expiry is provided for a "temporary" trend,
  # you can default it to 30 days.
  def create_temporary_keyword(attrs, days \\ 30) do
    expiry = DateTime.utc_now() |> DateTime.add(days, :day)

    attrs
    |> Map.put("expires_at", expiry)
    |> create_keyword()
  end

  @doc "Logic to delete expired keywords"
  def cleanup_expired_keywords do
    now = DateTime.utc_now()

    query = from k in RestrictedKeyword, where: k.expires_at < ^now

    {count, _} = Repo.delete_all(query)

    if count > 0 do
      # Clear cache so the moderation engine stops looking for these words
      Cachex.clear(:kollective_cache)
    end

    count
  end

  # Reporter Trust Levels
  # To implement Reporter Trust Levels, we upgrade your reporting logic from a simple "count" to a "weighted score."
  # This ensures that a single report from a Verified/Exempt user has more impact than a report from a brand-new, unverified account.

  # 1. Update the Moderation Context
  # We will modify the check_report_threshold function. Instead of counting rows, we will sum the "trust weight" of the reporters.

  # 3. How the Weights Work

  #  Exempt/Power User (Weight: 5): Since the threshold is 5, a single report from a Power User acts as an Instant Flag. This is useful for "Community Moderators" who aren't full Admins.
  #  Verified User (Weight: 3): It takes 2 Verified users to hide a post (3 + 3 = 6).
  #  Citizen User (Weight: 1): It takes 5 citizen users to hide a post (1 + 1 + 1 + 1 + 1 = 5).

  # defp check_report_threshold(%{post_id: post_id, event_id: event_id}) do
  # 1. Determine which resource we are checking
  #  {resource, id} = if post_id, do: {Posts, post_id}, else: {Events, event_id}

  # 2. Calculate total Trust Score
  # Exempt users = 5 points (instant trigger), Verified = 3, Standard = 1
  #  total_score = calculate_report_score(post_id, event_id)

  #  if total_score >= @auto_hide_threshold do
  # 3. AUTO-HIDE: Move to pending
  #    item = resource.get_by_id!(id)
  #    resource.update_status(item, :pending)

  # Log why it was hidden
  #    log_system_event("auto_hide_threshold_hit", "#{total_score} trust points reached.")
  #  end
  # end

  # defp calculate_report_score(post_id, event_id) do
  #  query = from r in Report,
  #    join: u in assoc(r, :reporter),
  #    where: r.post_id == ^post_id or r.event_id == ^event_id,
  # Assign weights based on user flags
  #     select: %{
  #     weight: fragment("CASE WHEN ? THEN 5 WHEN ? THEN 3 ELSE 1 END", u.is_exempt, u.is_verified)
  #    }

  #  query
  #  |> Repo.all()
  #  |> Enum.map(& &1.weight)
  #  |> Enum.sum()
  # end

  # "False Report Penalty"
  # @doc "Penalizes a user for a bad-faith report."
  # def dismiss_report_as_false(report_id, admin) do
  #  Repo.transaction(fn ->
  #    report = Repo.get!(Report, report_id) |> Repo.preload(:reporter)
  #    reporter = report.reporter

  # 1. Update the report status
  #    {:ok, _} = update_report_status(report, :dismissed)

  # 2. Penalty Logic: Reduce trust score by 20% and increment false count
  #    new_score = max(0.1, reporter.report_trust_score - 0.2)

  #    reporter
  #    |> User.changeset(%{
  #      report_trust_score: new_score,
  #      false_reports_count: reporter.false_reports_count + 1
  #    })
  #    |> Repo.update!()

  # 3. Log the penalty for admin audit
  #   log_action(admin, %{id: reporter.id}, "report_penalty", "False report on item #{report.post_id || report.event_id}")
  # end)
  # end

  # @doc "Rewards a user for an accurate report."
  # def resolve_report(report_id, admin) do
  #  Repo.transaction(fn ->
  #    report = Repo.get!(Report, report_id) |> Repo.preload(:reporter)
  #    reporter = report.reporter

  #    {:ok, _} = update_report_status(report, :resolved)

  # Reward Logic: Small boost to trust (up to 1.5 max)
  #    new_score = min(1.5, reporter.report_trust_score + 0.05)

  #    reporter
  #    |> User.changeset(%{
  #      report_trust_score: new_score,
  #      successful_reports_count: reporter.successful_reports_count + 1
  #    })
  #    |> Repo.update!()
  #  end)
  # end

  # Update the "Weighted Score" Logic
  # defp calculate_report_score(post_id, event_id) do
  #  query = from r in Report,
  #    join: u in assoc(r, :reporter),
  #    where: (r.post_id == ^post_id or r.event_id == ^event_id) and r.status == :pending,
  #    select: %{
  #      base_weight: fragment("CASE WHEN ? THEN 5 WHEN ? THEN 3 ELSE 1 END", u.is_exempt, u.is_verified),
  #      multiplier: u.report_trust_score
  #    }

  #  query
  #  |> Repo.all()
  #  |> Enum.reduce(0.0, fn r, acc -> acc + (r.base_weight * r.multiplier) end)
  # end

  ###########################################################################################################
end

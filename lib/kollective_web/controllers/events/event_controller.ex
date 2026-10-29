defmodule KollectiveWeb.EventController do
  use KollectiveWeb, :controller
  alias Kollective.Repo
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events
  alias Kollective.Moderation.Moderation
  alias Kollective.Security.Security
  alias Kollective.Workers.{EventAlertWorker, SecurityAlertWorker}
  alias KollectiveWeb.{ChangesetJSON, EventJSON}

  # Apply the same rate limit as posts (or stricter, e.g., 2 events/min)
  plug(KollectiveWeb.Plugs.RateLimiter when action in [:create])

  # GET /api/v1/events
  # Destructure params to capture the incoming optional "cursor" string query param
  def index(conn, params) do
    user = conn.assigns[:current_user]
    cursor = Map.get(params, "cursor")
    limit = 50

    # 1. Build base visibility query scope matching user authorization context
    base_query = Events.list_visible_events_query(user)

    # 2. Dynamically apply cursor filtering and page sizing constraints
    paginated_query =
      base_query
      |> Events.apply_cursor_pagination_events(cursor, limit)

    # 3. Fetch current segment rows from Postgres
    raw_events = Kollective.Repo.all(paginated_query)

    # 4. Inject transient user join (RSVP/Interested) membership flags if logged in
    events =
      if user do
        Events.attach_user_join_states(raw_events, user)
      else
        raw_events
      end

    # 5. Extract the ID of the last item in the list array to serve as the next page pointer
    next_cursor =
      case List.last(events) do
        nil -> nil
        last_item -> to_string(last_item.id)
      end

    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events, next_cursor: next_cursor}))
  end

  # GET /api/v1/events
  def indexX(conn, _params) do
    user = conn.assigns[:current_user]

    events =
      if user do
        Events.list_visible_events_query(user)
        |> Kollective.Repo.all()
        |> Events.attach_user_join_states(user)
      else
        Events.list_visible_events_query(nil)
        |> Kollective.Repo.all()
      end

    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events}))
  end

  # POST /api/v1/events/filter_by_date
  def filter_by_date(conn, params) do
    user = conn.assigns[:current_user]
    events = Events.list_events_filtered(user, params) |> Events.attach_user_join_states(user)

    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events}))
  end

  # ─── ACTION 1: FETCH DASHBOARD FEED CARD (WITH USER RSVP STATE) ───
  # GET /api/v1/kollective/events/:id
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]
    event = Events.get_event!(id)

    # Fetch the user's active RSVP state record mapping to this event node
    my_rsvp =
      if current_user do
        Repo.get_by(Kollective.Events.Participant, event_id: event.id, user_id: current_user.id)
      else
        nil
      end

    rsvp_status_str = if my_rsvp, do: my_rsvp.status, else: nil

    # Inject the value into the preloaded struct map virtual field safely
    event_with_status =
      if rsvp_status_str, do: Map.put(event, :join_state, rsvp_status_str), else: event

    # Present via your strict uniform EventJSON data schema format contract
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: EventJSON.data(event_with_status)
    })
  end

  # ─── ACTION 2: RETRIEVE ALL EVENTS JOINED BY CURRENT USER ───
  # GET /api/v1/kollective/events/joined
  def joined_events(conn, params) do
    user = conn.assigns.current_user
    events = Events.list_joined_events_for_user(user, params)

    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events}))
  end

  # ─── ACTION: RETRIEVE NEARBY EVENTS FOR USER WITHIN GIVEN RADIUS ───
  # GET /api/v1/events/nearby
  def nearby(conn, params) do
    user = conn.assigns[:current_user]
    events = Events.list_nearby_events(user, params)

    conn
    |> put_status(:ok)
    |> json(EventJSON.index(%{events: events}))
  end

  # ─── ACTION 3: DISPATCH SOCIAL EVENT INVITE DIALOG TABS ───
  # POST /api/v1/kollective/events/:id/invite
  def invite(conn, %{"id" => event_id, "user_id" => target_user_id}) do
    inviter = conn.assigns.current_user
    event = Events.get_event!(event_id)

    # Security Guard: Only the organizer can invite to a private, locked space
    if event.join_mode == "invite_only" and event.created_by != inviter.id do
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "forbidden",
        message: "Only the organizer can invite users to this private event."
      })
    else
      # Reuses your high-performance, atomic invitation context module
      case Events.invite_to_private_event(inviter, event.id, target_user_id) do
        {:ok, :invited} ->
          conn
          |> put_status(:ok)
          |> json(%{status: "success", message: "Invitation sent successfully."})

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "failed_to_send"})
      end
    end
  end

  # ─── ACTION 4: DOWNLOAD STANDARD CALENDAR EVENT (.ICS ATTACHMENT) ───
  # GET /api/v1/kollective/events/:id/ics
  def download_ics(conn, %{"id" => id}) do
    event = Events.get_event!(id)

    # Format timestamps according to international calendar database conventions
    tz_str = event.timezone || "UTC"
    start_str = Events.format_ical_datetime(event.start_time, tz_str)

    end_time = event.end_time || DateTime.add(event.start_time, 2, :hour)
    end_str = Events.format_ical_datetime(end_time, tz_str)

    # Generate RFC 5545 compliant multi-platform iCal feed text block
    ics_content = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Kollective//NONSGML Standalone Calendar Engine//EN
    CALSCALE:GREGORIAN
    BEGIN:VEVENT
    SUMMARY:#{event.title}
    DTSTART;TZID=#{tz_str}:#{start_str}
    DTEND;TZID=#{tz_str}:#{end_str}
    DESCRIPTION:#{String.replace(event.description || "", "\n", "\\n")}
    LOCATION:#{event.location_name}
    STATUS:CONFIRMED
    SEQUENCE:1
    END:VEVENT
    END:VCALENDAR
    """

    conn
    |> put_resp_content_type("text/calendar")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{event.title}.ics\"")
    |> send_resp(200, String.trim(ics_content))
  end

  @doc """
  Unified Event Creation Controller Action. Handles complex parameter checking,
  fraud identification gates, automated two-strike IP banning, and strategic black-hole responses.
  """
  # POST /api/v1/events
  def create(conn, params) do
    event_params = Map.get(params, "event", params)
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    # 1. EVALUATE CONTENT: Single-pass text scanning through the unified moderation matrix
    # Returns: {:error, :forbidden_content, msg}, {:ok, :published}, or {:ok, :pending}
    case Moderation.determine_status(user, event_params) do
      {:error, :forbidden_content, matched_word} ->
        # ─── FRAUD GATING: AUTOMATED TWO-STRIKE REJECTION BLOCK WITH WORD TRACKING ───
        # Append the offending phrase to the user's local memory cache loop
        Moderation.track_denied_word(user.id, matched_word)

        # Increment their offense counter in memory using Hammer (10-minute rolling window)
        # case Hammer.check_rate("post_denied:#{user.id}", 600_000, 1) do
        # Call your exact reference function to check for a cooldown lock
        case Moderation.record_denial(user.id) do
          :cooldown ->
            # SECOND STRIKE: Cooldown hit! Total Black Hole (Fake Success)
            # 1. Retrieve all words triggered in this 10-minute window for the audit log
            triggered_words = Moderation.get_denied_words(user.id)
            notes_string = "Triggered words in window: #{triggered_words}"

            # 2. Instantly blacklist their IP address in Cachex memory for 1 hour
            Security.blacklist_ip_temporary(
              ip,
              :timer.hours(1)
            )

            # 3. Automatically flag and shadow-ban the user account globally for spam
            Accounts.flag_user_for_spam("user:#{user.id}")

            # 4. Queue a high-importance administrative security alert worker job via Oban
            # Log security alert
            enqueue_security_alert("cooldown_triggered", user.id, ip, 2, notes_string)

            # 5. Short-circuit connection and return a fake success response to trick the attacker
            black_hole_response(conn)

          :ok ->
            # FIRST STRIKE: Return an explicit validation error to guide real users
            # Alert admins of the initial attempt asynchronously via Oban
            # Log security alert
            enqueue_security_alert(
              "hard_ban_attempt",
              user.id,
              ip,
              1,
              "Triggered word: #{matched_word}"
            )

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Your post contains prohibited language."})
            |> halt()
        end

      {:ok, status} ->
        # ─── NORMAL PROCESSING: Handles clear (:published) and soft-banned (:pending) states ───
        status_str = Atom.to_string(status)
        final_params = Map.put(event_params, "status", status_str)

        # 2. Hand off cleanly to your core atomic Ecto.Multi event context engine
        case Events.create_event(user, final_params) do
          {:ok, preloaded_event} ->
            # 3. ASYNC BACKGROUND WORKFLOW ROUTING
            if status == :pending do
              # Offload heavy HTTP email actions completely into an isolated Oban queue worker
              %{"event_id" => preloaded_event.id, "user_id" => user.id}
              |> EventAlertWorker.new()
              |> Oban.insert!()
            end

            # FAKE SUCCESS STRATEGY: Present :published back to the client even if internally pending
            # Override the string directly inside the preloaded map before passing to the serializer
            final_event = %{preloaded_event | event_status: "published"}

            conn
            |> put_status(:created)
            # Explicitly targets your exact EventJSON.data format contract payload
            |> json(%{
              status: "success",
              data: EventJSON.data(final_event)
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ChangesetJSON.error(%{changeset: changeset}))
        end
    end
  end

  # --- Structural Output Response & Log Helpers ---
  defp black_hole_response(conn) do
    # Fake success payload response mimicking a valid creation footprint
    conn
    |> put_status(:created)
    |> json(%{
      status: "success",
      message: "Event successfully submitted and queued for area approval lookups."
    })
    |> halt()
  end

  defp enqueue_security_alert(type, user_id, ip, strikes, notes) do
    %{
      "type" => type,
      "user_id" => user_id,
      "ip" => ip,
      "strikes" => strikes,
      "notes" => notes
    }
    |> SecurityAlertWorker.new()
    |> Oban.insert!()
  end

  # PUT /api/v1/kollective/events/:id
  def update(conn, %{"id" => id} = params) do
    event_params = Map.get(params, "event", Map.delete(params, "id"))
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    # 1. Fetch the existing event from the database first
    case Events.get_event(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found."})

      {:ok, event} ->
        # 2. OWNERSHIP GUARD: Stop bad actors from modifying other users' groups
        is_creator = event.created_by == user.id
        is_staff = user.is_admin or user.is_moderator

        if not (is_creator or is_staff) do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You are not authorized to edit this event."})
        else
          # 3. MODERATION SCAN: Pipe edits through the unified five-priority matrix
          case Moderation.determine_status(user, event_params) do
            {:error, :forbidden_content, matched_word} ->
              # TWO-STRIKE BLACKLIST GATING
              Moderation.track_denied_word(user.id, matched_word)

              case Moderation.record_denial(user.id) do
                :cooldown ->
                  triggered_words = Moderation.get_denied_words(user.id)

                  Security.blacklist_ip_temporary(
                    ip,
                    :timer.hours(1)
                  )

                  Accounts.flag_user_for_spam("user:#{user.id}")

                  enqueue_security_alert(
                    "cooldown_triggered",
                    user.id,
                    ip,
                    2,
                    "Triggered words: #{triggered_words}"
                  )

                  black_hole_response(conn)

                :ok ->
                  enqueue_security_alert(
                    "hard_ban_attempt",
                    user.id,
                    ip,
                    1,
                    "Triggered word: #{matched_word}"
                  )

                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Your edits contain prohibited language."})
                  |> halt()
              end

            {:ok, status} ->
              # Inject the parsed compliance status token directly into attributes map strings
              status_str = Atom.to_string(status)
              final_params = Map.put(event_params, "status", status_str)

              # 4. EXECUTE LOCAL UPDATE PIPELINE
              case Events.update_event(user, event.id, final_params) do
                {:ok, updated_event} ->
                  # Trigger an alert if modified state slips into soft-ban review queue
                  if status == :pending do
                    %{"event_id" => updated_event.id, "user_id" => user.id}
                    |> Kollective.Workers.EventAlertWorker.new()
                    |> Oban.insert!()
                  end

                  # Hide shadow state from bad actors (Fake Success Strategy)
                  final_event = %{updated_event | event_status: "published"}

                  conn
                  |> put_status(:ok)
                  # Output matching your exact EventJSON.data contract payload
                  |> json(%{
                    status: "success",
                    data: EventJSON.data(final_event)
                  })

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(ChangesetJSON.error(%{changeset: changeset}))
              end
          end
        end
    end
  end

  # DELETE /api/v1/kollective/events/:id
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Events.cancel_event(user, id) do
      {:ok, :cancelled} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Event successfully deleted and attendees notified."
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "unauthorized", message: "You don't own this event."})
    end
  end

  # lib/kollective_web/controllers/admin/moderation_controller.ex
  # POST /api/v1/admin/reports/:report_id/resolve_event
  def resolve_flagged_event(conn, %{"report_id" => report_id}) do
    admin = conn.assigns.current_admin

    case Events.admin_cancel_event(admin, report_id) do
      {:ok, :admin_cancelled} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Event successfully pulled from the timeline."})

      {:error, :event_already_deleted} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_action", message: "Event was already pulled."})
    end
  end

  # --- Cachex Word-Tracking Operations ---

  # defp track_denied_word(user_id, word) do
  #  Moderation.track_denied_word(user_id, word)
  # end

  # defp get_denied_words(user_id) do
  #  Moderation.get_denied_words(user_id)
  # end

  defp guest_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end

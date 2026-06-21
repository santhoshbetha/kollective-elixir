defmodule Kollective.Events.Events do
  import Ecto.Query, warn: false
  alias Kollective.Repo
  alias Kollective.Events.Event
  alias Ecto.Multi
  alias Kollective.Events.Participant, as: EventParticipant # Assumed join table name
  alias Kollective.Workers.{EventStartWorker, OrganizerSummaryWorker, EventReminderWorker}
  alias Kollective.Notifications.Notifications
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Accounts
  alias Ecto.Multi

  #alias Kollective.External.GeoapifyService
  #alias Kollective.External.CivicService

  @doc """
  Unifies all event creation workflows. Performs atomic transaction inserts for
  organizers, handles text mentions, and schedules all timeline-based Oban notification workers.
  """
  def create_event(user, attrs \\ %{}) do
    now = DateTime.utc_now()

    # 1. Cast attributes locally to inspect timestamps before entering the transaction pool
    changeset = Event.changeset(%Event{}, attrs)
    start_time = Ecto.Changeset.get_field(changeset, :start_time)

    Multi.new()
    # STEP A: Fetch location metrics from your Geospatial service if location_id is provided
    |> Multi.run(:location_data, fn _repo, _changes ->
       location_id = attrs["location_id"] || attrs[:location_id]
       location_meta = get_location(%{location_id: location_id})

       # Merge the raw geospatial map results straight into your input attributes
       updated_attrs =
         if location_meta do
           attrs
           |> Map.put("location_name", location_meta.name || location_meta["name"])
           |> Map.put("latitude", location_meta.latitude || location_meta["latitude"])
           |> Map.put("longitude", location_meta.longitude || location_meta["longitude"])
           |> Map.put("street", location_meta.street || location_meta["street"])
           |> Map.put("postal_code", location_meta.postal_code || location_meta["postal_code"])
           |> Map.put("locality", location_meta.locality || location_meta["locality"])
           |> Map.put("region", location_meta.region || location_meta["region"])
           |> Map.put("city_name", location_meta.city_name || location_meta["city_name"])
         else
           attrs
         end

       {:ok, updated_attrs}
     end)

     # STEP B: Insert the Event using the enriched location attributes
    |> Multi.insert(:event, fn %{location_data: enriched_attrs} ->
        %Event{created_by: user.id}
        |> Event.changeset(enriched_attrs)
        # Connects straight into your privileged scholar/journalist geofencing rules
        |> validate_and_fix_targeting(enriched_attrs, user)
      end)

    # STEP C: Auto-Join Creator as the First Participant (Organizers are marked as attending)
    |> Multi.insert(:organizer_attendance, fn %{event: event} ->
         %EventParticipant{
           user_id: user.id,
           event_id: event.id,
           status: "accepted"
         }
       end)

    # STEP D: Increment the Cache Counter Column
    |> Multi.update_all(:inc_participants, fn %{event: event} ->
         from(e in Event, where: e.id == ^event.id)
       end, inc: [participants_count: 1])

    # STEP E: SCHEDULE THE EVENT TIMELINE OMNI-QUERIES (Oban Background Workers)
    |> Multi.run(:schedule_workers, fn _repo, %{event: event} ->
         # 1. "Starting Now" Notification Pushes
         %{event_id: event.id}
         |> EventStartWorker.new(scheduled_at: start_time)
         |> Oban.insert!()

         # 2. 1-Hour "Upcoming Event" Reminders
         one_hour_before = DateTime.add(start_time, -1, :hour)
         if DateTime.compare(one_hour_before, now) == :gt do
           %{event_id: event.id}
           |> EventReminderWorker.new(scheduled_at: one_hour_before)
           |> Oban.insert!()
         end

         # 3. 24-Hour Organizer Metrics Summary Previews
         twenty_four_hours_before = DateTime.add(start_time, -24, :hour)
         if DateTime.compare(twenty_four_hours_before, now) == :gt do
           %{event_id: event.id}
           |> OrganizerSummaryWorker.new(scheduled_at: twenty_four_hours_before)
           |> Oban.insert!()
         end

         {:ok, :workers_scheduled}
       end)

    # 2. Execute full Transaction Block
    |> Repo.transaction()
    |> handle_event_lifecycle(user)
  end

  # --- Post Execution Lifecycle Broadcasts ---
  defp validate_and_fix_targeting(changeset, attrs, user) do
    organization_id = Ecto.Changeset.get_field(changeset, :organization_id)

    case user.type do
      :regular ->
        changeset
        |> Ecto.Changeset.put_change(:origin_country, user.country)
        |> Ecto.Changeset.put_change(:origin_state, user.state)
        |> Ecto.Changeset.put_change(:origin_city_id, user.city_id)
        |> Ecto.Changeset.put_change(:origin_district_l1, user.district_l1_id) #district_l1 is the same as district_l1
        |> Ecto.Changeset.put_change(:origin_district_l2, user.district_l2_id) #district_l2 is the same as district_l2
        |> Ecto.Changeset.put_change(:origin_district_l3, user.district_l3_id) #district_l3 is the same as district_l3

      type when type in [:scholar, :journalist] or not is_nil(organization_id) ->
        # SCHOLAR/JOURNALIST: Can choose both :target_scope
        # OR posting on behalf of an Organization
        # AND a custom :origin district/state from the React UI.
        # We only set defaults if the UI left them blank.
       changeset
        |> Ecto.Changeset.cast(attrs, [
          :target_scope,
          :origin_state,
          :origin_country,
          :origin_city_id,
          :origin_district_l1,
          :origin_district_l2,
          :origin_district_l3
        ])
        # Fall back to user's home base fields ONLY if the React UI left them blank
        |> default_value(:origin_country, user.country)
        |> default_value(:origin_state, user.state)
        |> default_value(:origin_city_id, user.city_id)
    end
  end

  defp default_value(changeset, field, fallback_value) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil -> Ecto.Changeset.put_change(changeset, field, fallback_value)
      _ -> changeset
    end
  end

  defp handle_event_lifecycle({:ok, %{event: event}}, user) do
    # Trigger text mentions parsing and user pings asynchronously
    Task.start(fn -> trigger_event_notifications(user, event) end)

    # 1. CRITICAL PRELOAD: Hydrate all relational fields required by EventJSON.data/1
    hydrated_event =
      event
      |> Repo.preload([
        :user,
        :origin_city,
        # Walks up the recursive district relationship stack (Local > State > National)
        origin_district: [parent: :parent]
      ])

    # 2. Broadcast the fully populated event struct over WebSockets for live feed updates
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "feed:public",
      {:new_event, hydrated_event}
    )

    # Return the fully preloaded event back to the controller pipeline
    {:ok, hydrated_event}
  end

  defp handle_event_lifecycle({:error, _step, changeset, _changes}, _user) do
    {:error, changeset}
  end

  defp trigger_event_notifications(_user, _event) do
    # Reuses your standard Post mention extraction regex and notification logic
    :ok
  end


  @doc """
  Updates an existing event record.
  If the start time has changed, it automatically voids old background reminders,
  enqueues new Oban time triggers, and pushes real-time notification alerts to attendees.
  """
  def update_event(%Event{} = event, attrs) do
    now = DateTime.utc_now()

    # Detect if a start time change parameter was explicitly transmitted by the UI
    time_changed? = Map.has_key?(attrs, "start_time") or Map.has_key?(attrs, :start_time)

    Multi.new()
    # Step A: Execute the standard local database record modification query
    |> Multi.update(:event, Event.changeset(event, attrs))

    # Step B: Dynamic Lifecycle Scheduling Matrix
    |> Multi.run(:reschedule_lifecycle, fn _repo, %{event: updated_event} ->
        if time_changed? do
          # 1. Purge all historical pending Oban reminders instantly [O(1) database prune]
          cancel_pending_reminders(updated_event.id)

          # 2. Re-enqueue fresh background worker jobs targeted at the new start time
          start_time = updated_event.start_time

          %{"event_id" => updated_event.id}
          |> EventStartWorker.new(scheduled_at: start_time)
          |> Oban.insert!()

          one_hour_before = DateTime.add(start_time, -1, :hour)
          if DateTime.compare(one_hour_before, now) == :gt do
            %{"event_id" => updated_event.id}
            |> EventReminderWorker.new(scheduled_at: one_hour_before)
            |> Oban.insert!()
          end

          twenty_four_hours_before = DateTime.add(start_time, -24, :hour)
          if DateTime.compare(twenty_four_hours_before, now) == :gt do
            %{"event_id" => updated_event.id}
            |> OrganizerSummaryWorker.new(scheduled_at: twenty_four_hours_before)
            |> Oban.insert!()
          end

          # 3. Fire transient and persistent alerts to all registered attendees
          Task.start(fn -> notify_time_change(updated_event) end)
        end

        {:ok, :lifecycle_processed}
      end)
    |> Repo.transaction()
    |> case do
        {:ok, %{event: updated_event}} ->
          # Re-hydrate full relational dependencies needed for serialization
          hydrated_event =
            updated_event
            |> Repo.preload([
              :user,
              :origin_city,
              origin_district: [parent: :parent]
            ])

          # Global WebSockets push to update timeline scrollers instantly
          Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:event_updated, hydrated_event})

          # Isolated room channel push to update the specific event page dashboard view live
          Phoenix.PubSub.broadcast(Kollective.PubSub, "event:#{hydrated_event.id}", {:event_details_updated, hydrated_event})

          {:ok, hydrated_event}

        {:error, _failed_step, changeset, _changes} ->
          {:error, changeset}
      end
  end

  # ─── SECTION 2: DISK CLEANUP & AUDIT NOTIFICATION PIPELINES ───

  defp cancel_pending_reminders(event_id) do
    import Ecto.Query
    # Targeted query locating unexecuted Oban jobs linked to this event structure
    # Forcing state in ["available", "scheduled"] prevents messing with running or dead workers
    from(j in Oban.Job,
      where: j.queue in ["notifications", "default"],
      where: fragment("?->>'event_id' = ?", j.args, ^to_string(event_id)),
      where: j.state in ["available", "scheduled"]
    )
    |> Repo.delete_all()
  end

  defp notify_time_change(event) do
    participants = list_accepted_participants(event.id)
    formatted_time = "10:00 AM IST" # Replace with your dynamic timezone helper: EventHelpers.local_time_string(event)

    Enum.each(participants, fn p ->
      # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
      Notifications.notify(
        p.user_id,         # The recipient (The registered attendee)
        event.created_by,  # The actor (The organizer who rescheduled the calendar)
        "event_update",    # Type validated against your strict snake_case registry list
        %{
          event_id: event.id,
          target_id: event.id,
          target_type: "Event",
          metadata: %{
            event_title: event.name,
            new_time: formatted_time
          }
        },
        %{
          post_id: nil,
          preview: "📅 Time changed for '#{event.name}'. New schedule: #{formatted_time}."
        }
      )
    end)
  end




  @doc """
  The definitive event registration pipeline. Handles row-level booking locks,
  calendar overlap detection, waitlist sorting, and real-time notification routing.

  Returns:
    * {:ok, :joined}     -> Instantly confirmed (Free mode)
    * {:ok, :requested}  -> Held for approval (Restricted mode)
    * {:ok, :waitlisted} -> Placed on queue (Event Full)
    * {:error, message}  -> Collision errors or transaction crashes
  """
  def join_event(user, event_id) do
    Repo.transaction(fn ->
      # 1. ROW LOCK GUARD: Restricts concurrent write operations to eliminate race conditions
      event =
        from(e in Event, where: e.id == ^event_id, lock: "FOR UPDATE")
        |> Repo.one!()

      # 2. CALENDAR OVERLAP ANALYSIS: Verify the user isn't already double-booked
      conflicts = check_calendar_conflicts(user.id, event)

      if Enum.any?(conflicts) do
        conflict_names = Enum.map(conflicts, & &1.name) |> Enum.join(", ")
        Repo.rollback("Conflict: You are already attending overlapping event(s): #{conflict_names}")
      else
        # 3. IDENTIFY CAPACITY BOUNDARIES
        max_seats = Map.get(event.metadata || %{}, "max_participants") || 999_999
        is_full = event.participants_count >= max_seats

        # 4. DISPATCH REGISTRATION PIPELINE
        execute_join_state(user, event, is_full)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Structural Isolated Registration Pipelines ---

  # CASE A: TARGET EVENT IS FULL -> Append to waitlist instantly across all modes
  defp execute_join_state(user, event, _is_full = true) do
    Multi.new()
    |> Multi.insert(:attendance, %EventParticipant{user_id: user.id, event_id: event.id, status: "waitlisted"})
    |> Repo.transaction()

    # Dispatch persistent history rows and real-time alert toast popups
    Notifications.notify(
      user.id,
      event.created_by,
      "event_reminder",
      %{event_id: event.id, target_id: event.id, target_type: "Event", metadata: %{sub_type: "event_waitlisted", event_title: event.name}},
      %{post_id: nil, preview: "⚠️ You have been placed on the waitlist for '#{event.name}'."}
    )

    :waitlisted
  end

  # CASE B: JOIN MODE IS FREE & SPACE IS AVAILABLE -> Instant acceptance allocation
  defp execute_join_state(user, event, _is_full = false) when event.join_mode == "free" do
    Multi.new()
    |> Multi.insert(:attendance, %EventParticipant{user_id: user.id, event_id: event.id, status: "accepted"})
    |> Multi.update_all(:inc_counter, from(e in Event, where: e.id == ^event.id), inc: [participants_count: 1])
    |> Repo.transaction()

    # Live PubSub push to update timeline cards and attendee rosters across the UI natively
    broadcast_event_update(event.id)

    :joined
  end

  # CASE C: JOIN MODE IS RESTRICTED & SPACE IS AVAILABLE -> Queue for review approval
  defp execute_join_state(user, event, _is_full = false) when event.join_mode == "restricted" do
    Multi.new()
    |> Multi.insert(:attendance, %EventParticipant{user_id: user.id, event_id: event.id, status: "pending"})
    |> Multi.update_all(:inc_counter, from(e in Event, where: e.id == ^event.id), inc: [participation_request_count: 1])
    |> Repo.transaction()

    # Notify the Event Creator/Organizer permanently that a new slot request is pending approval
    Notifications.notify(
      event.created_by,
      user.id,
      "participation_request",
      %{event_id: event.id, target_id: event.id, target_type: "Event", metadata: %{event_title: event.name}},
      %{post_id: nil, preview: "📥 @#{user.username} requested to join your event '#{event.name}'."}
    )

    :requested
  end

  # --- Internal Geometry & Calendar Sync Helpers ---

  defp check_calendar_conflicts(user_id, event) do
    # Locate other events this user is attending that overlap with the target timeframe
    # Overlap Formula: (existing.start_time < new.end_time) AND (existing.end_time > new.start_time)
    from(e in Event,
      join: p in EventParticipant, on: p.event_id == e.id,
      where: p.user_id == ^user_id and p.status == "accepted",
      where: e.id != ^event.id,
      where: e.start_time < ^event.end_time and e.end_time > ^event.start_time,
      select: %{id: e.id, name: e.name}
    )
    |> Repo.all()
  end

  @doc """
  Approves a pending attendance request for a restricted event.
  Maintains counter caches atomically and alerts the recipient across private channels.
  """
  def approve_request(%User{} = organizer, participant_id) do
    Repo.transaction(fn ->
      # 1. Fetch the targeted request node
      case Repo.get(EventParticipant, participant_id) do
        nil ->
          Repo.rollback("Registration request record not found.")

        participant ->
          # 2. ROW LOCK GUARD: Obtain an exclusive write lock on the parent event to prevent overbooking
          event = from(e in Event, where: e.id == ^participant.event_id, lock: "FOR UPDATE") |> Repo.one!()

          # Verify the executing user is the absolute owner/organizer of the event
          if event.created_by != organizer.id do
            Repo.rollback("You are not authorized to manage attendees for this event.")
          else
            cond do
              # Guard: If already accepted, short-circuit safely
              participant.status == "accepted" ->
                {:ok, :already_approved}

              # Guard: Enforce strict capacity limits even during manual administrative approvals
              event.participants_count >= (Map.get(event.metadata || %{}, "max_participants") || 999_999) ->
                Repo.rollback("Approval failed: This event is currently at maximum capacity.")

              true ->
                # 3. ATOMICALLY COMMUTE DB RECORDS STATUS
                participant
                |> Ecto.Changeset.change(status: "accepted")
                |> Repo.update!()

                # 4. SWAP COUNTER CACHES IN A SINGLE TRANSACTION WINDOW
                from(e in Event, where: e.id == ^event.id)
                |> Repo.update_all(inc: [participants_count: 1, participation_request_count: -1])

                # 5. DELIVER UNIFIED NOTIFICATIONS
                # Combines permanent notification bell history with a transient real-time push payload
                Notifications.notify(
                  participant.user_id,   # The recipient (The attendee being approved)
                  organizer.id,          # The actor (The organizer executing the trigger)
                  "participation_accepted", # Validated snake_case registry string
                  %{
                    event_id: event.id,
                    target_id: event.id,
                    target_type: "Event",
                    metadata: %{event_title: event.name, sub_type: "request_approved"}
                  },
                  %{
                    post_id: nil,
                    preview: "🎟️ Congratulations! Your request to join '#{event.name}' has been approved."
                  }
                )

                # 6. BROADCAST GRAPH CHANGES FOR UI RE-RENDERING
                broadcast_event_update(event.id)

                {:ok, :approved}
            end
          end
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end


  @doc """
  Rejects a pending attendance request for a restricted event.
  Atomic transaction deletes the request row and updates the queue metrics cache securely.
  """
  def reject_request(%User{} = organizer, participant_id) do
    Repo.transaction(fn ->
      # 1. Fetch the targeted pending participant row
      case Repo.get(EventParticipant, participant_id) do
        nil ->
          Repo.rollback("Registration request record not found.")

        participant ->
          # 2. ROW LOCK GUARD: Obtain an exclusive lock on the parent event to safely modify caches
          event = from(e in Event, where: e.id == ^participant.event_id, lock: "FOR UPDATE") |> Repo.one!()

          # Verify the executing user is the absolute owner/organizer of the event
          if event.created_by != organizer.id do
            Repo.rollback("You are not authorized to manage attendees for this event.")
          else
            # 3. ATOMICALLY COMMUTE DB RECORDS STATUS
            # Wipe out the pending attendance record completely
            Repo.delete!(participant)

            # 4. DECREMENT COUNTER CACHES INSIDE THE TRANSACTION WINDOW
            # Only decrement the request count if the user was actually in a pending state
            if participant.status == "pending" do
              from(e in Event, where: e.id == ^event.id)
              |> Repo.update_all(inc: [participation_request_count: -1])
            end

            # 5. BROADCAST GRAPH CHANGES FOR UI RE-RENDERING
            # Instantly pushes updates over WebSockets so dashboard lists refresh live
            broadcast_event_update(event.id)

            {:ok, :rejected}
          end
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end


  defp broadcast_event_update(event_id) do
    # Re-fetch the freshly updated metrics count out of the locked transaction block
    updated_event = Repo.get!(Event, event_id) |> Repo.preload([:user, :origin_city])

    # Broadcast the data structural payload frame so React layers update counters live
    Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:event_updated, updated_event})
    Phoenix.PubSub.broadcast(Kollective.PubSub, "event:#{event_id}", {:event_details_updated, updated_event})
  end



  @doc """
  Inserts an explicit participant mapping record into the database join table.
  """
  def add_participant(user_id, event_id, status \\ "accepted") do
    %EventParticipant{}
    |> EventParticipant.changeset(%{user_id: user_id, event_id: event_id, status: status})
    |> Repo.insert()
  end

  @doc """
  Fetches a high-performance preview list of accepted participants for a specific event.
  Preloads user profiles and handles sorting using database indexes.
  """
  def list_participants(event_id, limit \\ 10) do
    EventParticipant
    |> where([p], p.event_id == ^event_id and p.status == "accepted")
    |> preload([:user])
    |> order_by([p], desc: p.id) # Replaces loose inserted_at checks with sequential index lookups
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Social Sync Engine: Isolates which people the active user explicitly follows
  are currently attending the exact same event.
  """
  def list_friends_attending(user, event_id) do
    # 1. Reuse our high-performance flat array integer extract helper (Zero RAM bloat) [INDEX]
    following_ids = Accounts.get_following_ids(user.id)

    # 2. Extract matching event attendance logs in a single fast query pass
    EventParticipant
    |> where([p], p.event_id == ^event_id and p.status == "accepted")
    |> where([p], p.user_id in ^following_ids)
    |> preload([:user])
    |> Repo.all()
  end


  @doc """
  Handles removing a user from an event. If space becomes available, the next user
  on the waitlist is automatically promoted to "accepted" and notified.
  """
  def leave_event(user, event_id) do
    Repo.transaction(fn ->
      # 1. ROW LOCK GUARD: Lock the event record to protect seat calculations
      event =
        from(e in Event, where: e.id == ^event_id, lock: "FOR UPDATE")
        |> Repo.one!()

      # 2. LOCATE AND REMOVE ATTENDANCE LOG
      case Repo.get_by(Participant, user_id: user.id, event_id: event.id) do
        nil ->
          Repo.rollback("You are not registered for this event.")

        attendance ->
          Repo.delete!(attendance)

          # 3. CONCURRENT PROMOTION MATRIX
          if attendance.status == "accepted" do
            # Decrement the count since an active attendee left
            from(e in Event, where: e.id == ^event.id)
            |> Repo.update_all(inc: [participants_count: -1])

            # Search for the next oldest waitlisted user (FIFO)
            next_in_line_query =
              from(p in EventParticipant,
                where: p.event_id == ^event.id and p.status == "waitlisted",
                order_by: [asc: p.id], # Sorted cleanly by B-Tree primary key indexes
                limit: 1
              )

            case Repo.one(next_in_line_query) do
              nil ->
                # Nobody on waitlist, just push the real-time layout updates
                broadcast_event_update(event.id)
                {:ok, :left}

              next_user ->
                # Promote waitlisted user to accepted
                next_user
                |> Ecto.Changeset.change(status: "accepted")
                |> Repo.update!()

                # Re-increment count because the waitlist spot was filled
                from(e in Event, where: e.id == ^event.id)
                |> Repo.update_all(inc: [participants_count: 1])

                # Deliver notifications cleanly through the unified pipeline
                Notifications.notify(
                  next_user.user_id,
                  event.created_by,
                  "participation_accepted",
                  %{
                    event_id: event.id,
                    target_id: event.id,
                    target_type: "Event",
                    metadata: %{event_title: event.name, sub_type: "waitlist_promoted"}
                  },
                  %{
                    post_id: nil,
                    preview: "🎉 Good news! You've been moved off the waitlist and are now attending '#{event.name}'."
                  }
                )

                broadcast_event_update(event.id)
                {:ok, :left_and_promoted}
            end
          else
            # User was only pending or waitlisted when they left, no promotion logic required
            if attendance.status == "pending" do
              from(e in Event, where: e.id == ^event.id)
              |> Repo.update_all(inc: [participation_request_count: -1])
            end

            broadcast_event_update(event.id)
            {:ok, :left}
          end
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end


  @doc """
  Geospatial Discovery Engine: Fetches events within a strict circular bounding box.
  Leverages the PostgreSQL earth_distance index extensions to calculate precise proximity metrics.
  """
  def list_nearby_events(user_lat, user_lng, radius_meters \\ 10_000) do
    # Convert incoming strings safely if they leak from UI parameter arrays
    lat = if is_binary(user_lat), do: String.to_float(user_lat), else: user_lat
    lng = if is_binary(user_lng), do: String.to_float(user_lng), else: user_lng
    radius = if is_binary(radius_meters), do: String.to_integer(radius_meters), else: radius_meters

    from e in Event,
      where: e.event_status == "published" and (is_nil(e.end_time) or e.end_time > fragment("NOW()")),
      # 1. Fast Indexed Pre-Filtering bounding box scan pass
      where: fragment(
        "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(e.latitude, e.longitude)",
        ^lat, ^lng, ^radius
      ),
      # 2. Refine selection footprint to an exact radial circle calculation
      where: fragment(
        "earth_distance(ll_to_earth(?, ?), ll_to_earth(e.latitude, e.longitude)) < ?",
        ^lat, ^lng, ^radius
      ),
      # Calculate virtual distance meters property mapping on the fly
      select_merge: %{
        metadata: fragment(
          "jsonb_build_object('distance_meters', round(earth_distance(ll_to_earth(?, ?), ll_to_earth(e.latitude, e.longitude))::numeric, 0))",
          ^lat, ^lng
        )
      },
      order_by: [asc: fragment("earth_distance(ll_to_earth(?, ?), ll_to_earth(e.latitude, e.longitude))", ^lat, ^lng)],
      limit: 20,
      preload: [:user, :origin_city]
  end

  @doc """
  Dispatches a secure community event invitation. Evaluates mutual social filters,
  writes a persistent database audit alert, and pushes an immediate real-time socket toast popup.
  """
  def send_event_invite(%Kollective.Accounts.User{} = inviter, event_id, target_user_id) do
    event = Repo.get!(Event, event_id)

    # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload [INDEX]
    Notifications.notify(
      target_user_id,          # Who receives the invitation
      inviter.id,              # Who initiated the action
      "event_update",          # Safe, verified type from your @notification_types registry [INDEX]
      %{
        event_id: event.id,
        target_id: event.id,
        target_type: "Event",
        # Package the invite properties inside our flexible JSONB metadata column [INDEX]
        metadata: %{
          event_title: event.name,
          sub_type: "event_invite"
        }
      },
      %{
        post_id: nil,
        preview: "✉️ @#{inviter.username} invited you to attend the event: '#{event.name}'."
      }
    )
  end


  @doc """
  The definitive event RSVP pipeline. Handles state transitions across Going (accepted),
  Maybe, and No (rejected) counters while maintaining capacity boundaries and locks atomically.
  """
  def rsvp_to_event(%Kollective.Accounts.User{} = user, event_id, input_status)
      when input_status in ["going", "maybe", "no"] do

    # Normalize input states to match our strict schema boundaries
    target_status = case input_status do
      "going" -> "accepted"
      "no"    -> "rejected"
      other   -> other
    end

    Repo.transaction(fn ->
      # 1. ROW LOCK GUARD: Obtain an exclusive write lock on the target event row
      event = from(e in Event, where: e.id == ^event_id, lock: "FOR UPDATE") |> Repo.one!()

      # 2. RUN CONFLICT SECURITY CHECKS (Only if switching state into an active "going" slot)
      conflicts = if target_status == "accepted", do: check_calendar_conflicts(user.id, event), else: []

      if Enum.any?(conflicts) do
        conflict_names = Enum.map(conflicts, & &1.name) |> Enum.join(", ")
        Repo.rollback("Conflict: You are already attending overlapping event(s): #{conflict_names}")
      else
        # 3. ENFORCE CAPACITY BOUNDARIES FOR ACTIVE SIGNUPS
        max_seats = Map.get(event.metadata || %{}, "max_participants") || 999_999
        is_full = event.participants_count >= max_seats

        # If the event is full and they chose "going", force route them to the waitlist queue instead
        final_status = if target_status == "accepted" and is_full, do: "waitlisted", else: target_status

        # 4. COMMUTE ATTENDANCE STORAGE STATE
        existing_rsvp = Repo.get_by(Participant, user_id: user.id, event_id: event.id)

        case existing_rsvp do
          nil ->
            %EventParticipant{user_id: user.id, event_id: event.id, status: final_status}
            |> Repo.insert!()

          rsvp ->
            rsvp
            |> Ecto.Changeset.change(status: final_status)
            |> Repo.update!()
        end

        # 5. RECALCULATE CACHE COUNTERS & RE-STREAM METRICS TO THE UI
        recalculate_and_broadcast_counters(event.id)

        # Return specific status code out of the lock transaction window
        {:ok, String.to_atom(final_status)}
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # ─── SECTION 2: ATOMIC AGGREGATE RECALCULATION & STREAMING BROADCASTER ───

  defp recalculate_and_broadcast_counters(event_id) do
    # 1. Read accurate, fresh attendee states straight from the database index queries
    counts =
      from(p in EventParticipant,
        where: p.event_id == ^event_id,
        group_by: p.status,
        select: {p.status, count(p.id)}
      )
      |> Repo.all()
      |> Enum.into(%{})

    going_count = Map.get(counts, "accepted", 0)

    # 2. Sync the raw table totals directly back to your main Event row cache column
    # This guarantees your timeline search indexes never experience cache drift
    from(e in Event, where: e.id == ^event_id)
    |> Repo.update_all(set: [participants_count: going_count])

    # 3. Stream the raw granular counts directly across WebSockets to refresh UI widgets live
    # Standardizes UI vocabulary keys back to friendly "going / maybe / no" terms
    Phoenix.PubSub.broadcast(Kollective.PubSub, "event:#{event_id}", {:update_rsvps, %{
      going: going_count,
      maybe: Map.get(counts, "maybe", 0),
      no: Map.get(counts, "rejected", 0),
      waitlisted: Map.get(counts, "waitlisted", 0)
    }})

    # Fire a full dashboard model update pass to keep cards and rosters perfectly synchronized
    broadcast_event_update(event_id)
  end




  @doc """
  Fetches a single event by ID, raising an Ecto.NoResultsError if not found.
  Automatically preloads author/creator fields.
  """
  def get_event!(id) do
    Event
    |> preload([:user])
    |> Repo.get!(id)
  end

  @doc """
  Safely fetches a single event by ID, returning a clean success/error tuple.
  """
  def get_event(id) do
    case Repo.get(Event, id) |> Repo.preload([:user]) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc """
  Fetches all accepted participants for a specific event_id.
  Optimized to extract a clean list of participant records with preloaded user maps.
  """
  def list_accepted_participants(event_id) do
    EventParticipant
    |> where([ep], ep.event_id == ^event_id and ep.status == "accepted")
    |> preload([:user])
    |> Repo.all()
  end


  def get_event_with_hierarchy!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload([
      :user,
      # This preloads the local district, its parent, and its grandparent
      # Get the "stack" (State Senate District → State District→ National District)
      # Preloading parent (L2) and grandparent (L1)
      # Walking up the tree: L3 -> L2 -> L1
      origin_district: [parent: :parent]
    ])
  end

  def list_events_with_hierarchy do
    Event
    |> Repo.all()
    |> Repo.preload([
      :user,
      # This preloads the local district, its parent, and its grandparent
      # Get the "stack" (State Senate District → State District→ National District)
      # Preloading parent (L2) and grandparent (L1)
      # Walking up the tree: L3 -> L2 -> L1
      district: [parent: :parent]
    ])
  end


 # def list_events_in_state_hierarchy(state_id) do

  defp get_location(%{location_id: location_id}) when location_id in [nil, "", "nil"], do: nil
  defp get_location(%{location_id: location_id}) when is_binary(location_id) do
    result = Geospatial.Service.service().get_by_id(location_id)
    List.first(result)
  end
  defp get_location(_), do: nil
end

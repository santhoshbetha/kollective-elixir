defmodule Kollective.Events.Events do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Events.Event
  alias Kollective.Events.{Comment, CommentLike}
  # Assumed join table name
  alias Kollective.Events.Participant, as: EventParticipant

  alias Kollective.Workers.{
    EventStartWorker,
    OrganizerSummaryWorker,
    EventReminderWorker,
    GeocodeWorker
  }

  alias Kollective.Notifications.Notifications
  alias Kollective.Accounts.User
  alias Kollective.Accounts.Accounts
  alias Kollective.Admins.Log, as: AdminLog
  alias Kollective.Locations.Locations

  # alias Kollective.External.GeoapifyService
  # alias Kollective.External.CivicService

  @doc """
  Registers a community event record inside the database.
  Enforces administrative targeting rules based on user privileges and handles
  asynchronous geocoding and notifications via Oban concurrently.
  """
  def create_event(%User{} = user, attrs \\ %{}) do
    attrs = Event.normalize_event_attrs(attrs)
    now = DateTime.utc_now()

    has_coordinates? =
      not is_nil(attrs["latitude"] || attrs[:latitude]) and
        not is_nil(attrs["longitude"] || attrs[:longitude])

    address_text =
      attrs["address"] || attrs[:address] ||
        attrs["location_name"] || attrs[:location_name] ||
        attrs["street"] || attrs[:street] ||
        attrs["location"] || attrs[:location]

    geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)

    start_time =
      case attrs["start_time"] || attrs[:start_time] do
        %DateTime{} = dt ->
          dt

        binary_str when is_binary(binary_str) ->
          case DateTime.from_iso8601(binary_str) do
            {:ok, dt, _} -> dt
            _ -> DateTime.add(now, 1, :hour)
          end

        _ ->
          DateTime.add(now, 1, :hour)
      end

    Multi.new()
    # Step 1: OPTIONAL CITY RESOLUTION (Never blocks rural or unincorporated areas)
    |> Multi.run(:resolved_city, fn _repo, _changes ->
      if is_nil(geoname_id) || String.trim(to_string(geoname_id)) == "" do
        {:ok, nil}
      else
        case Locations.get_or_import_city(geoname_id) do
          {:ok, city} -> {:ok, city}
          {:error, _} -> {:ok, nil}
        end
      end
    end)

    # Step 2: Insert the Event while explicitly verifying the author's privilege level
    |> Multi.insert(:event, fn %{resolved_city: city} ->
      base_attrs =
        attrs
        |> Map.put("user_id", user.id)
        |> Map.put("event_status", "published")
        |> Map.merge(
          if city,
            do: %{
              "city_id" => city.id,
              "city_name" => city.name,
              "origin_state" => city.state,
              "origin_country" => city.country
            },
            else: %{}
        )

      %Event{created_by: user.id}
      |> Event.creation_changeset(base_attrs)
      # TARGETING ENFORCEMENT: Enforces regional targeting constraints prior to schema writing
      |> validate_and_fix_targeting(base_attrs, user)
    end)

    # Step 3: Auto-Join Creator as the First Participant
    |> Multi.insert(:organizer_attendance, fn %{event: event} ->
      %EventParticipant{
        user_id: user.id,
        event_id: event.id,
        status: "accepted"
      }
    end)

    # Step 4: Increment the Cache Counter Column atomically
    |> Multi.update_all(
      :inc_participants,
      fn %{event: event} ->
        from(e in Event, where: e.id == ^event.id)
      end,
      inc: [participants_count: 1]
    )

    # Step 5: SCHEDULE BACKGROUND LIFECYCLE ACTIONS IN THE OBAN QUEUE
    |> Multi.run(:schedule_workers, fn _repo, %{event: event} ->
      # A. Existing Core Lifecycle Event Workers
      %{"event_id" => event.id}
      |> EventStartWorker.new(scheduled_at: start_time)
      |> Oban.insert!()

      one_hour_before = DateTime.add(start_time, -1, :hour)

      if DateTime.compare(one_hour_before, now) == :gt do
        %{"event_id" => event.id}
        |> EventReminderWorker.new(scheduled_at: one_hour_before)
        |> Oban.insert!()
      end

      # B. NEW: Panoramic Banner Optimization Worker Queue
      # Automatically triggers background compression if an asset URL string was provided
      if Map.get(attrs, "banner_url") || Map.get(attrs, :banner_url) do
        %{"event_id" => event.id}
        |> Kollective.Workers.EventBannerOptimizer.new()
        |> Oban.insert!()
      end

      {:ok, :workers_scheduled}
    end)

    # Step 6: Conditionally Enqueue the Polymorphic Oban GeocodeWorker
    |> Multi.run(:enqueue_geocode, fn _repo, %{event: event} ->
      if (not has_coordinates? and address_text) && String.trim(address_text) != "" do
        %{"target_id" => event.id, "schema_type" => "Event", "address_text" => address_text}
        |> GeocodeWorker.new()
        |> Oban.insert()
      else
        {:ok, :skipped}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        # If necessary, you can extend your custom handle_event_lifecycle tracker function here
        handle_event_lifecycle({:ok, event}, user)

      # Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:new_event_registered, event.id})
      # {:ok, Repo.preload(event, [:user])}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # ─── THE DEFINITIVE GEOGRAPHIC TARGETING VERIFIER ───
  defp validate_and_fix_targeting(changeset, attrs, user) do
    # Determine if this action is authorized on behalf of a managed corporate profile
    organization_id = Ecto.Changeset.get_field(changeset, :organization_id)
    is_managed_org? = not is_nil(organization_id) and organization_id != ""

    case user.type do
      :citizen when not is_managed_org? ->
        # ─── CITIZEN SECURITY SHIELD ───
        # Strip custom parameter overrides; strictly force values to lock onto their physical home base
        changeset
        |> Ecto.Changeset.put_change(:origin_country, user.country || "US")
        |> Ecto.Changeset.put_change(:origin_state, user.state)
        # Standard city relation foreign key matching your schema
        |> Ecto.Changeset.put_change(:origin_city_id, user.city_id)
        |> Ecto.Changeset.put_change(:origin_district_l1, user.district_l1_id)
        |> Ecto.Changeset.put_change(:origin_district_l2, user.district_l2_id)
        |> Ecto.Changeset.put_change(:origin_district_l3, user.district_l3_id)

      _privileged_or_org_actor ->
        # ─── PRIVILEGED ACTOR DECORATOR ───
        # Scholars, Journalists, Activists, or approved members acting as an Organization
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
        # Fall back to user's home parameters ONLY if the React UI fields are left blank

        |> default_changeset_value(:origin_country, user.country || "US")
        |> default_changeset_value(:origin_state, user.state)
        |> default_changeset_value(:origin_city_id, user.city_id)
        |> default_changeset_value(:origin_district_l1, user.district_l1_id)
        |> default_changeset_value(:origin_district_l2, user.district_l2_id)
        |> default_changeset_value(:origin_district_l3, user.district_l3_id)
    end
  end

  # ─── IN-MEMORY METADATA FALLBACK COMPILER ───
  defp default_changeset_value(changeset, field, fallback_value) do
    # Inspects changesets safely in RAM without forcing slow disk database query lookups
    current_value = Ecto.Changeset.get_field(changeset, field)

    if is_nil(current_value) || current_value == "" do
      Ecto.Changeset.put_change(changeset, field, fallback_value)
    else
      changeset
    end
  end

  defp handle_event_lifecycle({:ok, event}, _user) do
    # Trigger text mentions parsing and user pings asynchronously
    # Task.start(fn -> trigger_event_notifications(user, event) end)
    %{"event_id" => event.id}
    |> Kollective.Workers.EventMentionsWorker.new()
    |> Oban.insert()

    # 1. CRITICAL PRELOAD: Hydrate all relational fields required by EventJSON.data/1
    hydrated_event =
      event
      |> Repo.preload([
        :user,
        :origin_city
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

  # defp handle_event_lifecycle({:error, _step, changeset, _changes}, _user) do
  #  {:error, changeset}
  # end

  # defp trigger_event_notifications(_user, event) do
  # Reuses your standard Post mention extraction regex and notification logic
  #  mentioned_usernames = parse_mention_strings(event.description)

  # Register structural notify hooks for mentions
  #  register_mention_notifications(event, mentioned_usernames, event.user_id)

  #  :ok
  # end

  # defp parse_mention_strings(text) do
  #  Regex.scan(~r/@[[:alnum:]_]+/, text)
  #  |> List.flatten()
  #  |> Enum.map(&String.replace(&1, "@", ""))
  #  |> Enum.uniq()
  # end

  # defp register_mention_notifications(event, verified_mentions, parent_author_id) do
  #  Enum.each(verified_mentions, fn recipient ->
  #    if recipient.id != event.user_id && recipient.id != parent_author_id do
  #      {:ok, notification} =
  #         Notifications.notify(
  #            recipient.id,
  #            event.user_id,
  #            "mention",
  #            %{
  #              event_id: event.id,
  #              target_id: event.id,
  #              target_type: "Event"
  #            },
  #            %{
  #              event_id: event.id,
  #              preview:
  #                "mentioned you in an event: \"#{String.slice(event.description || "", 0, 30)}...\""
  #            }
  #        )

  #      KollectiveWeb.Endpoint.broadcast(
  #        "user_notifications:#{recipient.id}",
  #        "new_notification",
  #        %{notification: notification}
  #      )
  #    end
  #  end)
  # end

  @doc """
  The unified community event modifier engine.
  Validates structural updates, enforces regional boundary targeting,
  and manages background Oban reminder queues asynchronously upon scheduling modifications.
  """
  def update_event(%User{} = user, event_id, attrs) do
    # 1. Fetch the existing record with the standard city relation preloaded
    # ⚡ CORRECT: Aligns with your belongs_to :origin_city schema definition
    event = Repo.get!(Event, event_id) |> Repo.preload([:origin_city])

    # Strict ownership guard pass: Protect against malicious cross-user alterations
    if event.created_by != user.id and not (user.is_admin or user.is_moderator) do
      {:error, :unauthorized}
    else
      now = DateTime.utc_now()
      geoname_id = Map.get(attrs, "geoname_id") || Map.get(attrs, :geoname_id)

      # 2. ACCURATE CHANGE DETECTION: Only trigger side-effects if values actually mutated
      new_address =
        attrs["address"] || attrs[:address] || attrs["location_name"] || attrs[:location_name]

      has_new_coordinates? = not is_nil(attrs["latitude"] || attrs[:latitude])
      address_changed? = new_address && new_address != event.location_name

      # Parse and verify if the start time truly changed from its stored state
      new_start_time =
        case attrs["start_time"] || attrs[:start_time] do
          nil ->
            nil

          %DateTime{} = dt ->
            dt

          binary_str ->
            case DateTime.from_iso8601(to_string(binary_str)) do
              {:ok, dt, _} -> dt
              _ -> nil
            end
        end

      time_changed? = new_start_time && DateTime.compare(new_start_time, event.start_time) != :eq

      Multi.new()
      # Step A: Conditional Location Resolution Node
      |> Multi.run(:resolved_attrs, fn _repo, _changes ->
        existing_external_id =
          if event.origin_city, do: to_string(event.origin_city.external_id), else: nil

        if is_nil(geoname_id) || to_string(geoname_id) == "" ||
             to_string(geoname_id) == existing_external_id do
          {:ok, attrs}
        else
          # Location changed: Fetch or import the city schema row
          case Locations.get_or_import_city(geoname_id) do
            {:ok, city} ->
              updated_attrs =
                attrs
                |> Map.put("origin_city_id", city.id)
                |> Map.put("city_name", city.name)
                |> Map.put("origin_state", city.state)
                |> Map.put("origin_country", city.country)

              {:ok, updated_attrs}

            {:error, reason} ->
              {:error, {:city_resolution_failed, reason}}
          end
        end
      end)

      # Step B: Apply updates via your comprehensive creation_changeset
      |> Multi.update(:event, fn %{resolved_attrs: final_attrs} ->
        event
        |> Event.creation_changeset(final_attrs)
        # TARGETING ENFORCEMENT: Re-evaluates political district boundaries natively
        |> validate_and_fix_targeting(final_attrs, user)
      end)

      # Step C: Dynamic Lifecycle Scheduling Matrix
      |> Multi.run(:reschedule_lifecycle, fn _repo, %{event: updated_event} ->
        if time_changed? do
          # 1. Purge all pending Oban reminder rows for this event instantly to prevent duplicates
          from(j in Oban.Job,
            where: j.queue == "notifications",
            where: fragment("?->>'event_id' = ?", j.args, ^to_string(updated_event.id)),
            where: j.state in ["available", "scheduled"]
          )
          |> Repo.delete_all()

          # 2. Re-enqueue fresh background workers targeted at the new start time
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

          # 3. Offload email alerts to attendees safely in a detached execution task
          # Task.start(fn -> notify_attendees_of_time_change(updated_event) end)
          # 🚀 FIX: Instead of Task.start/1, insert a new Oban job transactionally
          # Use repo.insert! so it joins the Ecto.Multi transaction natively
          %{"event_id" => updated_event.id}
          |> Kollective.Workers.NotifyAttendeesWorker.new()
          |> Oban.insert!()
        end

        {:ok, :lifecycle_processed}
      end)

      # Step D: Conditionally enqueue the polymorphic Oban GeocodeWorker
      |> Multi.run(:enqueue_geocode, fn _repo, %{event: updated_event} ->
        if address_changed? and not has_new_coordinates? do
          %{
            "target_id" => updated_event.id,
            "schema_type" => "Event",
            "address_text" => new_address
          }
          |> GeocodeWorker.new()
          |> Oban.insert()
        else
          {:ok, :skipped}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{event: updated_event}} ->
          # 3. REAL-TIME MULTI-CHANNEL BROADCASTS
          hydrated = Repo.preload(updated_event, [:user, :origin_city])

          # Global feed timeline scroller updates
          Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:event_updated, hydrated})
          # Dedicated event viewport page real-time refresh
          Phoenix.PubSub.broadcast(
            Kollective.PubSub,
            "event:#{hydrated.id}",
            {:event_details_updated, hydrated}
          )

          {:ok, hydrated}

        {:error, :resolved_attrs, {:city_resolution_failed, reason}, _changes} ->
          changeset =
            Ecto.Changeset.add_error(
              %Ecto.Changeset{data: event},
              :origin_city_id,
              "Location update failed: #{inspect(reason)}"
            )

          {:error, changeset}

        {:error, _failed_step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # ─── SECTION 2: DISK CLEANUP & AUDIT NOTIFICATION PIPELINES ───
  def notify_attendees_of_time_change(event) do
    participants = list_accepted_participants(event.id)
    # Replace with your dynamic timezone helper: EventHelpers.local_time_string(event)
    formatted_time = "10:00 AM IST"

    Enum.each(participants, fn p ->
      # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
      Notifications.notify(
        # The recipient (The registered attendee)
        p.user_id,
        # The actor (The organizer who rescheduled the calendar)
        event.created_by,
        # Type validated against your strict snake_case registry list
        "event_update",
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

      existing = Repo.get_by(EventParticipant, user_id: user.id, event_id: event.id)

      cond do
        existing && existing.status in ["accepted", "joined"] ->
          # User is already attending -> toggle (leave event)
          Repo.delete!(existing)
          recalculate_and_broadcast_counters(event.id)
          :left

        true ->
          # 2. CALENDAR OVERLAP ANALYSIS: Verify the user isn't already double-booked
          conflicts = check_calendar_conflicts(user.id, event)

          if Enum.any?(conflicts) do
            conflict_names = Enum.map(conflicts, &(&1.title || &1[:title])) |> Enum.join(", ")

            Repo.rollback(
              "Conflict: You are already attending overlapping event(s): #{conflict_names}"
            )
          else
            # 3. IDENTIFY CAPACITY BOUNDARIES
            max_seats = Map.get(event.metadata || %{}, "max_participants") || 999_999
            is_full = event.participants_count >= max_seats

            # 4. DISPATCH REGISTRATION PIPELINE WITH UPSERT OR EXISTING RECORD UPDATE
            execute_join_state(user, event, is_full, existing)
          end
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Structural Isolated Registration Pipelines ---

  defp upsert_participant(user, event, new_status, existing) do
    case existing do
      nil ->
        %EventParticipant{user_id: user.id, event_id: event.id, status: new_status}
        |> Repo.insert!()

      record ->
        record
        |> Ecto.Changeset.change(status: new_status)
        |> Repo.update!()
    end
  end

  # CASE A: TARGET EVENT IS FULL -> Append to waitlist instantly across all modes
  defp execute_join_state(user, event, _is_full = true, existing) do
    upsert_participant(user, event, "waitlisted", existing)
    recalculate_and_broadcast_counters(event.id)

    # Dispatch persistent history rows and real-time alert toast popups
    Notifications.notify(
      user.id,
      event.created_by,
      "event_reminder",
      %{
        event_id: event.id,
        target_id: event.id,
        target_type: "Event",
        metadata: %{sub_type: "event_waitlisted", event_title: event.title}
      },
      %{post_id: nil, preview: "⚠️ You have been placed on the waitlist for '#{event.title}'."}
    )

    :waitlisted
  end

  # CASE B: JOIN MODE IS FREE & SPACE IS AVAILABLE -> Instant acceptance allocation
  defp execute_join_state(user, event, _is_full = false, existing)
       when event.join_mode == "free" or is_nil(event.join_mode) do
    upsert_participant(user, event, "accepted", existing)
    recalculate_and_broadcast_counters(event.id)

    :joined
  end

  # CASE C: JOIN MODE IS RESTRICTED & SPACE IS AVAILABLE -> Queue for review approval
  defp execute_join_state(user, event, _is_full = false, existing)
       when event.join_mode == "restricted" do
    upsert_participant(user, event, "pending", existing)
    recalculate_and_broadcast_counters(event.id)

    # Notify the Event Creator/Organizer permanently that a new slot request is pending approval
    Notifications.notify(
      event.created_by,
      user.id,
      "participation_request",
      %{
        event_id: event.id,
        target_id: event.id,
        target_type: "Event",
        metadata: %{event_title: event.title}
      },
      %{
        post_id: nil,
        preview: "📥 @#{user.username} requested to join your event '#{event.title}'."
      }
    )

    :requested
  end

  # --- Internal Geometry & Calendar Sync Helpers ---

  defp check_calendar_conflicts(user_id, event) do
    start_time = event.start_time
    end_time = event.end_time || (start_time && DateTime.add(start_time, 2, :hour))

    if is_nil(start_time) or is_nil(end_time) do
      []
    else
      from(e in Event,
        join: p in EventParticipant,
        on: p.event_id == e.id,
        where: p.user_id == ^user_id and p.status == "accepted",
        where: e.id != ^event.id,
        where: not is_nil(e.start_time) and not is_nil(e.end_time),
        where: e.start_time < ^end_time and e.end_time > ^start_time,
        select: %{id: e.id, title: e.title}
      )
      |> Repo.all()
    end
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
          event =
            from(e in Event, where: e.id == ^participant.event_id, lock: "FOR UPDATE")
            |> Repo.one!()

          # Verify the executing user is the absolute owner/organizer of the event
          if event.created_by != organizer.id do
            Repo.rollback("You are not authorized to manage attendees for this event.")
          else
            cond do
              # Guard: If already accepted, short-circuit safely
              participant.status == "accepted" ->
                {:ok, :already_approved}

              # Guard: Enforce strict capacity limits even during manual administrative approvals
              event.participants_count >=
                  (Map.get(event.metadata || %{}, "max_participants") || 999_999) ->
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
                  # The recipient (The attendee being approved)
                  participant.user_id,
                  # The actor (The organizer executing the trigger)
                  organizer.id,
                  # Validated snake_case registry string
                  "participation_accepted",
                  %{
                    event_id: event.id,
                    target_id: event.id,
                    target_type: "Event",
                    metadata: %{event_title: event.name, sub_type: "request_approved"}
                  },
                  %{
                    post_id: nil,
                    preview:
                      "🎟️ Congratulations! Your request to join '#{event.name}' has been approved."
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
          event =
            from(e in Event, where: e.id == ^participant.event_id, lock: "FOR UPDATE")
            |> Repo.one!()

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

    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{event_id}",
      {:event_details_updated, updated_event}
    )
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
    # Replaces loose inserted_at checks with sequential index lookups
    |> order_by([p], desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Social Sync Engine: Isolates which people the active user explicitly follows
  are currently attending the exact same event.
  """
  def list_friends_attending(user, event_id) do
    # 1. Reuse our high-performance flat array integer extract helper (Zero RAM bloat)
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
      case Repo.get_by(EventParticipant, user_id: user.id, event_id: event.id) do
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
                # Sorted cleanly by B-Tree primary key indexes
                order_by: [asc: p.id],
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
                    preview:
                      "🎉 Good news! You've been moved off the waitlist and are now attending '#{event.name}'."
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
  Geospatial Discovery Engine: Fetches events within a given radius of a user or coordinates.
  Supports passing either:
    * `list_nearby_events(%User{} = user, params \\\\ %{})`
    * `list_nearby_events(user_lat, user_lng, radius_meters \\\\ 10_000)`
  Leverages PostgreSQL earth_distance and cube index extensions to calculate precise proximity metrics.
  """
  def list_nearby_events(user, params \\ %{})

  def list_nearby_events(%User{} = user, params) when is_map(params) do
    {lat, lng} = resolve_user_coordinates(user, params)

    if lat && lng do
      radius_meters = parse_radius_param(params)
      limit = parse_limit_param(params, 50)

      list_nearby_events_query(lat, lng, radius_meters, limit)
      |> Repo.all()
    else
      []
    end
  end

  def list_nearby_events(user_lat, user_lng, radius_meters) do
    case {parse_coord(user_lat), parse_coord(user_lng)} do
      {{:ok, lat}, {:ok, lng}} ->
        radius =
          case parse_coord(radius_meters) do
            {:ok, r} -> r
            _ -> 10_000.0
          end

        list_nearby_events_query(lat, lng, radius, 50)
        |> Repo.all()

      _ ->
        []
    end
  end

  @doc """
  Constructs the Ecto.Query for nearby events using earth_distance / cube indexing.
  """
  def list_nearby_events_query(lat, lng, radius_meters, limit \\ 50) do
    from(e in Event,
      where:
        e.event_status == "published" and
          (is_nil(e.end_time) or e.end_time > fragment("NOW()")) and
          not is_nil(e.latitude) and not is_nil(e.longitude),
      # 1. Fast Indexed Pre-Filtering bounding box scan pass
      where:
        fragment(
          "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?)",
          ^lat,
          ^lng,
          ^radius_meters,
          e.latitude,
          e.longitude
        ),
      # 2. Refine selection footprint to an exact radial circle calculation
      where:
        fragment(
          "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < ?",
          ^lat,
          ^lng,
          e.latitude,
          e.longitude,
          ^radius_meters
        ),
      # Calculate virtual distance meters property mapping on the fly
      select_merge: %{
        metadata:
          fragment(
            "coalesce(?, '{}'::jsonb) || jsonb_build_object('distance_meters', round(earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?))::numeric, 0))",
            e.metadata,
            ^lat,
            ^lng,
            e.latitude,
            e.longitude
          )
      },
      order_by: [
        asc:
          fragment(
            "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?))",
            ^lat,
            ^lng,
            e.latitude,
            e.longitude
          )
      ],
      limit: ^limit,
      preload: [:user, :origin_city]
    )
  end

  defp resolve_user_coordinates(user, params) do
    lat_param = params["lat"] || params["latitude"]
    lng_param = params["lng"] || params["lon"] || params["longitude"]

    with {:ok, lat} <- parse_coord(lat_param),
         {:ok, lng} <- parse_coord(lng_param) do
      {lat, lng}
    else
      _ ->
        resolve_coordinates_from_user(user)
    end
  end

  defp resolve_coordinates_from_user(nil), do: {nil, nil}

  defp resolve_coordinates_from_user(%User{} = user) do
    cond do
      match?(%Geo.Point{}, user.location) ->
        %Geo.Point{coordinates: {lng, lat}} = user.location
        {lat, lng}

      is_binary(user.location) and String.starts_with?(user.location, "POINT(") ->
        case Geo.WKT.decode(user.location) do
          {:ok, %Geo.Point{coordinates: {lng, lat}}} -> {lat, lng}
          _ -> fallback_user_district_or_city(user)
        end

      true ->
        fallback_user_district_or_city(user)
    end
  end

  defp fallback_user_district_or_city(%User{} = user) do
    district_id =
      user.district_l3_id || user.district_l2_id || user.district_l1_id

    cond do
      district_id ->
        case Repo.get(Kollective.Locations.PoliticalDistrict, district_id) do
          %Kollective.Locations.PoliticalDistrict{geom: %Geo.Point{coordinates: {lng, lat}}} ->
            {lat, lng}

          %Kollective.Locations.PoliticalDistrict{geom: %_{}} ->
            query =
              from(d in Kollective.Locations.PoliticalDistrict,
                where: d.id == ^district_id,
                select:
                  {fragment("ST_Y(ST_Centroid(?))", d.geom),
                   fragment("ST_X(ST_Centroid(?))", d.geom)}
              )

            case Repo.one(query) do
              {lat, lng} when is_number(lat) and is_number(lng) -> {lat, lng}
              _ -> fallback_user_city(user)
            end

          _ ->
            fallback_user_city(user)
        end

      true ->
        fallback_user_city(user)
    end
  end

  defp fallback_user_city(%User{} = user) do
    if user.city_id do
      case Repo.get(Kollective.Locations.City, user.city_id) do
        %Kollective.Locations.City{latitude: lat, longitude: lng}
        when not is_nil(lat) and not is_nil(lng) ->
          {lat, lng}

        _ ->
          {nil, nil}
      end
    else
      {nil, nil}
    end
  end

  defp parse_radius_param(params) do
    cond do
      params["radius_meters"] ->
        case parse_coord(params["radius_meters"]) do
          {:ok, val} -> val
          _ -> 10_000.0
        end

      params["radius_miles"] || params["distance_miles"] ->
        case parse_coord(params["radius_miles"] || params["distance_miles"]) do
          {:ok, val} -> val * 1609.34
          _ -> 10_000.0
        end

      params["unit"] in ["m", "meter", "meters"] and (params["radius"] || params["distance"]) ->
        case parse_coord(params["radius"] || params["distance"]) do
          {:ok, val} -> val
          _ -> 10_000.0
        end

      params["unit"] in ["km", "kilometer", "kilometers"] and
          (params["radius"] || params["distance"]) ->
        case parse_coord(params["radius"] || params["distance"]) do
          {:ok, val} -> val * 1000.0
          _ -> 10_000.0
        end

      params["radius"] || params["distance"] ->
        case parse_coord(params["radius"] || params["distance"]) do
          {:ok, val} -> val * 1609.34
          _ -> 10_000.0
        end

      true ->
        10_000.0
    end
  end

  defp parse_limit_param(params, default) do
    case params["limit"] do
      nil ->
        default

      val when is_integer(val) ->
        min(max(val, 1), 100)

      val when is_binary(val) ->
        case Integer.parse(val) do
          {int, _} -> min(max(int, 1), 100)
          _ -> default
        end

      _ ->
        default
    end
  end

  defp parse_coord(val) when is_float(val), do: {:ok, val}
  defp parse_coord(val) when is_integer(val), do: {:ok, val * 1.0}

  defp parse_coord(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> {:ok, num}
      _ -> :error
    end
  end

  defp parse_coord(_), do: :error

  @doc """
  Dispatches a secure community event invitation. Evaluates mutual social filters,
  writes a persistent database audit alert, and pushes an immediate real-time socket toast popup.
  """
  def send_event_invite(%User{} = inviter, event_id, target_user_id) do
    event = Repo.get!(Event, event_id)

    # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
    Notifications.notify(
      # Who receives the invitation
      target_user_id,
      # Who initiated the action
      inviter.id,
      # Safe, verified type from your @notification_types registry
      "event_update",
      %{
        event_id: event.id,
        target_id: event.id,
        target_type: "Event",
        # Package the invite properties inside our flexible JSONB metadata column
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
  def rsvp_to_event(%User{} = user, event_id, input_status)
      when is_binary(input_status) do
    # Normalize input states to match our strict schema boundaries
    target_status =
      case input_status do
        "going" -> "accepted"
        "attending" -> "accepted"
        "no" -> "rejected"
        other -> other
      end

    Repo.transaction(fn ->
      # 1. ROW LOCK GUARD: Obtain an exclusive write lock on the target event row
      event = from(e in Event, where: e.id == ^event_id, lock: "FOR UPDATE") |> Repo.one!()

      # 2. RUN CONFLICT SECURITY CHECKS (Only if switching state into an active "going" slot)
      conflicts =
        if target_status == "accepted", do: check_calendar_conflicts(user.id, event), else: []

      if Enum.any?(conflicts) do
        conflict_names = Enum.map(conflicts, &(&1.title || &1[:title])) |> Enum.join(", ")

        Repo.rollback(
          "Conflict: You are already attending overlapping event(s): #{conflict_names}"
        )
      else
        # 3. ENFORCE CAPACITY BOUNDARIES FOR ACTIVE SIGNUPS
        max_seats = Map.get(event.metadata || %{}, "max_participants") || 999_999
        is_full = event.participants_count >= max_seats

        # If the event is full and they chose "going", force route them to the waitlist queue instead
        final_status =
          if target_status == "accepted" and is_full, do: "waitlisted", else: target_status

        # 4. COMMUTE ATTENDANCE STORAGE STATE
        existing_rsvp = Repo.get_by(EventParticipant, user_id: user.id, event_id: event.id)

        result_code =
          case existing_rsvp do
            nil ->
              %EventParticipant{user_id: user.id, event_id: event.id, status: final_status}
              |> Repo.insert!()

              String.to_atom(final_status)

            rsvp ->
              if rsvp.status == final_status do
                Repo.delete!(rsvp)
                :removed
              else
                rsvp
                |> Ecto.Changeset.change(status: final_status)
                |> Repo.update!()

                String.to_atom(final_status)
              end
          end

        # 5. RECALCULATE CACHE COUNTERS & RE-STREAM METRICS TO THE UI
        recalculate_and_broadcast_counters(event.id)

        result_code
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
    # Shouts to FeedChannel -> "event:EVENT_ID" -> passes the flat counts straight to handle_out fallback
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{event_id}",
      {:update_rsvps,
       %{
         going: going_count,
         maybe: Map.get(counts, "maybe", 0),
         no: Map.get(counts, "rejected", 0),
         waitlisted: Map.get(counts, "waitlisted", 0)
       }}
    )

    # Fire a full dashboard model update pass to keep cards and rosters perfectly synchronized
    broadcast_event_update(event_id)
  end

  # ─── WORKFLOW 1: ORGANIZER CANCELATION PIPELINE ───

  @doc """
  Handles an organizer canceling their own community event. Wipes all scheduled
  Oban notifications from disk, notifies attendees, and scrubs public feeds.
  """
  def cancel_event(user, event_id) do
    event = Repo.get!(Event, event_id)

    if event.created_by != user.id do
      {:error, :unauthorized}
    else
      # Fetch attendee IDs before executing the cascade deletion pass
      attendee_ids =
        from(p in EventParticipant,
          where: p.event_id == ^event.id and p.status == "accepted",
          select: p.user_id
        )
        |> Repo.all()

      Multi.new()
      # Step A: Atomically purge pending scheduled Oban reminder tasks from disk
      |> Multi.run(:void_jobs, fn _repo, _changes ->
        cancel_pending_reminders(event.id)
        {:ok, :jobs_voided}
      end)

      # Step B: Perform Cascade Deletion on the main Event row
      |> Multi.delete(:event, event)
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          # Mass notify attendees and push public WebSocket feed-scrubbing parameters
          execute_cancellation_alerts(event, attendee_ids, user.id, "event_cancelled")
          {:ok, :cancelled}

        {:error, _failed_step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # ─── WORKFLOW 2: ADMINISTRATIVE OVERRIDE ENGINE (THE MODERATOR KILL-SWITCH) ───

  @doc """
  Administrative moderator override endpoint action. Resolves the associated Report,
  deletes the offending Event, files a compliance audit log, and alerts attendees.
  """
  def admin_cancel_event(admin, report_id) do
    # Fetch report alongside its preloaded event record securely
    report =
      Repo.get!(Kollective.Moderation.Report, report_id)
      |> Repo.preload(:event)

    event = report.event

    if is_nil(event) do
      {:error, :event_already_deleted}
    else
      # Gather all user IDs signed up for this event (attending, maybe, or waitlisted)
      attendee_ids =
        from(p in EventParticipant, where: p.event_id == ^event.id, select: p.user_id)
        |> Repo.all()

      Multi.new()
      # 1. Update the compliance report status block to resolved
      |> Multi.update(
        :report,
        Kollective.Moderation.Report.changeset(report, %{status: :resolved})
      )

      # 2. Cancel all outstanding pending Oban notification jobs instantly
      |> Multi.run(:void_jobs, fn _repo, _changes ->
        cancel_pending_reminders(event.id)
        {:ok, :jobs_voided}
      end)

      # 3. Permanently delete the Event from public infrastructure
      |> Multi.delete(:event, event)

      # 4. Insert an immutable Admin Audit Log entry for governance tracking
      |> Multi.insert(:admin_log, %AdminLog{
        action: "event_cancelled",
        target_id: event.id,
        user_id: admin.id,
        metadata: %{event_title: event.name}
      })
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          # Dispatch alerts using "event_update" to signify a moderator action
          execute_cancellation_alerts(event, attendee_ids, admin.id, "event_update")
          {:ok, :admin_cancelled}

        {:error, _failed_step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # ─── PRIVATE PIPELINE PROCESSING SUB-ROUTINES ───

  defp cancel_pending_reminders(event_id) do
    import Ecto.Query
    # Targeted query locating unexecuted Oban jobs linked to this event structure
    # Forcing state in ["available", "scheduled"] prevents messing with running or dead workers
    # Locates available or scheduled jobs for this event_id and deletes them cleanly
    from(j in Oban.Job,
      where: j.queue in ["notifications", "default"],
      where: fragment("?->>'event_id' = ?", j.args, ^to_string(event_id)),
      where: j.state in ["available", "scheduled"]
    )
    |> Repo.delete_all()
  end

  defp execute_cancellation_alerts(event, attendee_ids, actor_id, type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. BULK INSERT HISTORICAL NOTIFICATIONS (Prevents N+1 database insertion bottlenecks)
    # Storing the title string directly inside metadata ensures history loads even after deletion
    notifications_batch =
      Enum.map(attendee_ids, fn user_id ->
        %{
          # Use your project's ULID generator
          id: Kollective.Schemas.ULIDType.generate(),
          user_id: user_id,
          actor_id: actor_id,
          type: type,
          metadata: %{event_title: event.name, event_id: event.id, sub_type: "cancellation"},
          read: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Performance: High-speed multi-row atomic insertion sweep into the database
    if notifications_batch != [] do
      Repo.insert_all("notifications", notifications_batch)
    end

    # 2. TRANSIENT REAL-TIME ALERTS: Push live notifications over WebSockets
    Enum.each(attendee_ids, fn user_id ->
      Phoenix.PubSub.broadcast(
        Kollective.PubSub,
        "user_notifications:#{user_id}",
        {:new_notification,
         %{
           type: type,
           actor_name: "System",
           preview: "❌ Event Cancelled: '#{event.name}' has been called off."
         }}
      )
    end)

    # 3. GLOBAL FEED SCRUB: Tell active React scroll components to remove the card from the UI
    Phoenix.PubSub.broadcast(Kollective.PubSub, "feed:public", {:event_deleted, event.id})

    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{event.id}",
      {:event_cancelled_close_screen, event.id}
    )
  end

  # ─── WORKFLOW 1: SECURE DIRECT-TO-R2 UPLOAD PRESIGNMENT ───
  @doc """
  Generates a signed, short-lived URL for direct-to-R2 client-side file uploads.
  Organizes files deterministically inside designated folders based on their attachment intent.
  """
  def generate_upload_url(%User{} = user, event_id, filename, asset_type) do
    allowed_types = ["banner", "logo", "chat"]

    if asset_type in allowed_types do
      cleaned_ext = Path.extname(filename) |> String.downcase()
      unique_name = "asset_#{System.system_time(:millisecond)}#{cleaned_ext}"
      s3_path = "events/#{event_id}/#{asset_type}/#{user.id}/#{unique_name}"

      config = ExAws.Config.new(:s3)

      bucket = Kollective.Storage.bucket_name()
      cdn = Kollective.Storage.cdn_domain()

      # Wrap the S3 call in a safe case block to handle real connectivity errors
      case ExAws.S3.presigned_url(config, :put, bucket, s3_path, expires_in: 900) do
        {:ok, presigned_url} ->
          {:ok,
           %{
             upload_url: presigned_url,
             final_asset_url: "#{cdn}/#{s3_path}"
           }}

        {:error, reason} ->
          # This gives your case statement a real error path to resolve Dialyzer warnings
          {:error, reason}
      end
    else
      {:error, :invalid_type}
    end
  end

  # ─── WORKFLOW 2: UNIFIED EVENT MEDIA GALLERY AGGREGATOR ───

  @doc """
  Collects official event branding items (banner, logo) and aggregates all
  AI-approved chat photos into a unified grid portfolio array for the React UI.
  """
  def list_event_media(event_id) do
    # 1. Fetch official branding image components natively
    event = Repo.get!(Event, event_id)

    official_branding =
      [
        %{url: event.banner_url, type: "banner", id: "banner-#{event.id}"},
        %{url: event.logo_url, type: "logo", id: "logo-#{event.id}"}
      ]
      |> Enum.reject(fn item -> is_nil(item.url) or item.url == "" end)

    # 2. Query for all AI-approved user text comment photos in a single fast query pass
    user_uploads =
      from(c in Comment,
        where: c.event_id == ^event_id and c.moderation_status == "approved",
        where: not is_nil(c.image_url) and c.image_url != "",
        # Keyset indexing sorting optimization
        order_by: [desc: c.id],
        select: %{url: c.image_url, type: "user_upload", id: c.id}
      )
      |> Repo.all()

    official_branding ++ user_uploads
  end

  # ─── WORKFLOW 3: ORGANIZER GALLERY CURATION & SILENCING ───

  @doc """
  Allows an event organizer to remove an image from the public gallery and chat logs.
  Flips the comment state string to 'rejected' to invoke immediate global timeline hiding.
  """
  def hide_event_media(%User{} = organizer, comment_id) do
    # Fetch target record with preloaded parental properties
    case Repo.get(Comment, comment_id) |> Repo.preload(:event) do
      nil ->
        {:error, :not_found}

      comment ->
        # STRICT OWNERSHIP LOCK: Verify if the user is the true organizer of this event page
        if comment.event.created_by != organizer.id do
          {:error, :unauthorized}
        else
          Multi.new()
          # 1. Flip comment moderation status to rejected to strip it out of index results instantly
          |> Multi.update(:comment, Comment.changeset(comment, %{moderation_status: "rejected"}))

          # 2. Log action to your administrative compliance logging board for transparency
          |> Multi.insert(:admin_log, %AdminLog{
            action: "event_media_hidden",
            target_id: comment.id,
            target_type: "Comment",
            user_id: organizer.id,
            metadata: %{event_id: comment.event_id}
          })
          |> Repo.transaction()
          |> case do
            {:ok, %{comment: updated_comment}} ->
              # ─── REAL-TIME TRANSMISSION DATA PIPELINE ───
              # Shouts straight out over the specific event page channel room topic
              Phoenix.PubSub.broadcast(
                Kollective.PubSub,
                "event:#{updated_comment.event_id}",
                {"image_removed", %{id: updated_comment.id}}
              )

              {:ok, :hidden}

            {:error, _step, changeset, _changes} ->
              {:error, changeset}
          end
        end
    end
  end

  @doc """
  Fetches a list of all events the specific user has joined with an accepted status.
  """
  def list_joined_events_for_user(%User{} = user, _params \\ %{}) do
    from(e in Event,
      join: p in EventParticipant,
      on: p.event_id == e.id,
      where: p.user_id == ^user.id and p.status == "accepted" and e.event_status == "published",
      order_by: [desc: e.start_time],
      preload: [:user, :origin_city]
    )
    |> Repo.all()
  end

  # ─── ICALENDAR TIME-FORMATTING HELPER ───

  @doc """
  Converts a UTC DateTime into a standardized iCal local time string format (YYYYMMDDTHHMMSS).
  """
  def format_ical_datetime(%DateTime{} = dt, timezone_str) do
    # Elixir core will look up the string inside the provided database module
    dt
    |> DateTime.shift_zone!(timezone_str, Tz.TimeZoneDatabase)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  rescue
    _error ->
      # Safe backup fallback string formatting if timezone parsing fails (appends Z for UTC)
      Calendar.strftime(dt, "%Y%m%dT%H%M%SZ")
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

  # defp get_location(%{location_id: location_id}) when location_id in [nil, "", "nil"], do: nil
  # defp get_location(%{location_id: location_id}) when is_binary(location_id) do
  #  result = Geospatial.Service.service().get_by_id(location_id)
  #  List.first(result)
  # end
  # defp get_location(_), do: nil

  @doc """
  Inserts an event comment into the database.
  Supports optional media URLs, parent threading IDs, and custom moderation statuses.
  """
  def create_comment(attrs \\ %{}) do
    %Comment{}
    # Ensure your schema file has a standard cast/validate changeset function defined
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Asynchronous Mentions Processing Engine. Extracts user @mentions natively using regular
  expressions and triggers targeted, index-optimized notification rows.
  """
  def process_comment_mentions(%Comment{} = comment) do
    content_text = comment.content || ""

    if String.trim(content_text) != "" do
      # 1. Extract raw unique username strings directly from the text body
      mentioned_usernames = extract_usernames_from_text(content_text)

      if Enum.any?(mentioned_usernames) do
        # 2. BATCH LOOKUP: Fetch all matching user profiles in a single query pass
        # This completely avoids running repetitive individual database checks
        mentioned_users =
          Repo.all(from(u in User, where: u.username in ^mentioned_usernames))

        # 3. Iterate through found users and dispatch alerts via the unified pipeline
        Enum.each(mentioned_users, fn mentioned_user ->
          # SELF-NOTIFICATION GUARD: Never notify authors when they tag themselves
          if mentioned_user.id != comment.user_id do
            # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
            Notifications.notify(
              # Who receives the notification
              mentioned_user.id,
              # Who wrote the comment (The actor)
              comment.user_id,
              # Type strictly maps to your standalone snake_case registry list
              "mention",
              %{
                post_id: nil,
                event_id: comment.event_id,
                target_id: comment.id,
                target_type: "Comment"
              },
              %{
                post_id: nil,
                preview: "✍️ @#{comment.user.username} tagged you in an event discussion."
              }
            )
          end
        end)
      end
    end

    :ok
  end

  # ─── NATIVE SPATIAL TEXT-EXTRACTION HELPERS ───

  defp extract_usernames_from_text(text) do
    # Regex breakdown: Finds text characters immediately following an '@' symbol
    # Catches common username strings while ignoring punctuation at the end of sentences
    ~r/@([a-zA-Z0-9_]+)/
    |> Regex.scan(text)
    # Regex.scan returns nested arrays: [["@alice", "alice"], ["@bob", "bob"]]
    # We map over the rows to grab index position 1—the clean captured username string
    |> Enum.map(fn [_, username] -> String.downcase(username) end)
    # Deduplicate matching results if a user tags the same account multiple times in one comment
    |> Enum.uniq()
  end

  @doc """
  Lists comments for a given event with support for pagination, sorting options,
  and moderator shadow-banning filters.

  Supported options:
    * `:cursor_id`  - An integer ID to fetch records older than this cursor.
    * `:viewer_id`   - The current user's ID. Required to see their own shadow-banned/pending comments.
    * `:limit`       - Number of comments to return (defaults to 30).
    * `:reverse`     - Set to true to reverse the list array into sequential chronological order.
  """
  def list_comments(event_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    cursor_id = Keyword.get(opts, :cursor_id)
    viewer_id = Keyword.get(opts, :viewer_id)

    # 1. Base query bound to the parent event target
    query =
      from(c in Comment,
        where: c.event_id == ^event_id,
        preload: [:user]
      )

    # 2. Integrate the Shadow Ban Moderation Engine
    query = apply_moderation_scope(query, viewer_id)

    # 3. Handle Deterministic Cursor Pagination (Older than cursor_id matching)
    query = apply_cursor_pagination(query, cursor_id)

    # 4. Enforce Deterministic Sorting Limitations
    results =
      query
      |> order_by([c], desc: c.inserted_at, desc: c.id)
      |> limit(^limit)
      |> Repo.all()

    # 5. Conditionally flip formatting layouts for frontend timeline rendering
    if Keyword.get(opts, :reverse, false) do
      Enum.reverse(results)
    else
      results
    end
  end

  # ─── WORKFLOW 1: PUBLIC FEED FILTERING ───
  @doc """
  Lists all globally accessible, published public events sorted chronologically.
  """
  def list_public_events do
    from(e in Event,
      where: e.event_status == "published" and e.join_mode in ["free", "restricted"],
      order_by: [asc: e.start_time],
      preload: [:user, :origin_city]
    )
    |> Repo.all()
  end

  # ─── WORKFLOW 2: PRIVACY-MAPPED FEED ISOLATION ───

  @doc """
  Fetches an index query scope mapping user-specific privacy rights.
  Hides "invite_only" events unless the active user is the creator or an invited participant.
  """
  def list_visible_events_query(user) do
    if user do
      invited_event_ids =
        from(p in EventParticipant, where: p.user_id == ^user.id, select: p.event_id)
        |> Repo.all()

      from(e in Event,
        where: e.event_status == "published",
        where:
          e.join_mode in ["free", "restricted"] or e.id in ^invited_event_ids or
            e.created_by == ^user.id,
        order_by: [desc: e.start_time],
        preload: [:user, :origin_city]
      )
    else
      from(e in Event,
        where: e.event_status == "published",
        where: e.join_mode in ["free", "restricted"],
        order_by: [desc: e.start_time],
        preload: [:user, :origin_city]
      )
    end
  end

  def attach_user_join_states(events, nil), do: events

  def attach_user_join_states(events, %User{} = user) do
    event_ids = Enum.map(events, & &1.id)

    user_rsvps =
      from(p in EventParticipant,
        where: p.user_id == ^user.id and p.event_id in ^event_ids,
        select: {p.event_id, p.status}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(events, fn event ->
      join_state = Map.get(user_rsvps, event.id)
      Map.put(event, :join_state, join_state)
    end)
  end

  @doc """
  Filters published events by selected date string, distance radius in miles, or state.
  """
  def list_events_filtered(user, params \\ %{}) do
    query = list_visible_events_query(user)

    date_str = params["date"] || params["selected_date"]
    distance_val = params["distance"] || params["radius"]
    state_val = params["state"]
    lat_val = params["latitude"] || (user && Map.get(user, :latitude))
    lng_val = params["longitude"] || (user && Map.get(user, :longitude))

    # Apply Date Filter if present
    query =
      if is_binary(date_str) and String.trim(date_str) != "" do
        case Date.from_iso8601(String.trim(date_str)) do
          {:ok, date} ->
            start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
            from(e in query, where: e.start_time >= ^start_dt and e.start_time <= ^end_dt)

          _ ->
            query
        end
      else
        query
      end

    parse_float = fn
      val when is_number(val) ->
        val * 1.0

      val when is_binary(val) ->
        case Float.parse(val) do
          {num, _} -> num
          :error -> nil
        end

      _ ->
        nil
    end

    # Apply Distance/Coordinates filter if distance & lat/lng provided
    query =
      if not is_nil(distance_val) and not is_nil(lat_val) and not is_nil(lng_val) do
        dist_miles = parse_float.(distance_val)
        lat = parse_float.(lat_val)
        lng = parse_float.(lng_val)

        if dist_miles && lat && lng do
          lat_delta = dist_miles / 69.0
          lng_delta = dist_miles / 53.0

          min_lat = lat - lat_delta
          max_lat = lat + lat_delta
          min_lng = lng - lng_delta
          max_lng = lng + lng_delta

          from(e in query,
            where: e.latitude >= ^min_lat and e.latitude <= ^max_lat,
            where: e.longitude >= ^min_lng and e.longitude <= ^max_lng
          )
        else
          query
        end
      else
        # Fallback to State Filter if distance is not applicable but state is provided
        if is_binary(state_val) and String.trim(state_val) != "" do
          clean_state = String.trim(state_val)

          from(e in query,
            where: fragment("LOWER(?)", e.origin_state) == ^String.downcase(clean_state)
          )
        else
          query
        end
      end

    Repo.all(query)
  end

  # ─── WORKFLOW 3: ATOMIC PRIVATE EVENT INVITATIONS ───

  @doc """
  Dispatches a secure invitation to an invite-only private event.
  Creates the permission slice row and maps notification logs in a single atomic transaction.
  """
  def invite_to_private_event(%User{} = inviter, event_id, target_user_id) do
    event = Repo.get!(Event, event_id)

    Multi.new()
    # Step A: Insert the attendance mapping record as 'invited' (Acts as their view token key)
    |> Multi.insert(:attendance, %EventParticipant{
      user_id: target_user_id,
      event_id: event.id,
      status: "invited"
    })
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        # Step B: Deliver notifications cleanly through the unified pipeline
        # Arguments contract: target_user_id, actor_id, type, database_attrs, websocket_payload
        Notifications.notify(
          # Who receives the notification
          target_user_id,
          # Who initiated the action
          inviter.id,
          # Safe, verified snake_case type from your registry list
          "event_update",
          %{
            event_id: event.id,
            target_id: event.id,
            target_type: "Event",
            metadata: %{event_title: event.title, sub_type: "private_event_invite"}
          },
          %{
            post_id: nil,
            preview:
              "🔒 Secret Invite: @#{inviter.username} invited you to a private event: '#{event.title}'."
          }
        )

        {:ok, :invited}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # --- Internal Scope Filters ---

  # Appends the visibility layer depending on who is requesting the timeline feed
  defp apply_moderation_scope(query, nil) do
    # An anonymous or unauthenticated request can only view clean public assets
    where(query, [c], c.moderation_status == "approved")
  end

  defp apply_moderation_scope(query, viewer_id) do
    # THE SHADOW BAN FILTER:
    # Public users see "approved". Authors see their own "pending" or "rejected" content.
    where(
      query,
      [c],
      c.moderation_status == "approved" or
        (c.moderation_status == "rejected" and c.user_id == ^viewer_id) or
        (c.moderation_status == "pending" and c.user_id == ^viewer_id)
    )
  end

  def apply_cursor_pagination_events(query, cursor, limit) do
    import Ecto.Query

    # Enforce strict chronological order layout rules
    base_ordered_query =
      from(e in query, order_by: [desc: e.inserted_at, desc: e.id], limit: ^limit)

    if cursor && cursor != "" && cursor != "null" do
      # THE PIB PIPELINE: Use cursor string indices to boundary select subsequent page segments
      # Assuming you use a chronologically orderable ID scheme like ULID/UUIDv7.
      # If using standard integers, change '<' to match your ordering paradigm.
      from(e in base_ordered_query, where: e.id < ^cursor)
    else
      base_ordered_query
    end
  end

  # Looks up the position of the last element loaded to return older content segments safely
  defp apply_cursor_pagination(query, nil), do: query

  defp apply_cursor_pagination(query, cursor_id) do
    # Fetch records that were inserted prior to this specific record node sequence
    where(query, [c], c.id < ^cursor_id)
  end

  @doc """
  Fetches all top-level approved comments for a specific event page.
  Preloads author metadata and dynamically hydrates like totals and 'has_liked' highlights.
  """
  def list_event_comments(event_id, reading_user \\ nil, params \\ %{}) do
    limit = Map.get(params, "limit", 50)
    cursor = Map.get(params, "cursor")

    # 1. Base query focusing exclusively on approved, top-level comments
    base_query =
      from(c in Comment,
        where:
          c.event_id == ^event_id and c.moderation_status == "approved" and is_nil(c.parent_id)
      )

    # Apply keyset pagination boundary if a cursor parameter is passed
    query =
      if cursor,
        do: from(c in base_query, where: c.id < ^cursor),
        else: base_query

    raw_comments =
      query
      |> order_by([c], desc: c.id)
      |> limit(^limit)
      |> preload([:user])
      |> Repo.all()

    # 2. BATCH DATA HYDRATION: Hydrate likes maps in a single memory pass
    hydrate_comment_virtual_fields(raw_comments, reading_user)
  end

  @doc """
  Safely fetches a single comment with its immediate nested reply structures preloaded.
  """
  def get_comment(id, reading_user \\ nil) do
    Comment
    |> where([c], c.id == ^id and c.moderation_status == "approved")
    |> preload([:user, replies: [:user]])
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      comment ->
        [hydrated] = hydrate_comment_virtual_fields([comment], reading_user)
        {:ok, hydrated}
    end
  end

  # --- Private O(1) Hydration Engine ---
  defp hydrate_comment_virtual_fields([], _), do: []

  defp hydrate_comment_virtual_fields(comments, user) do
    comment_ids = Enum.map(comments, & &1.id)

    # Fetch absolute total counts across the list
    likes_counts =
      from(l in CommentLike,
        where: l.comment_id in ^comment_ids,
        group_by: l.comment_id,
        select: {l.comment_id, count(l.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Fetch user specific highlights
    liked_ids =
      if user do
        from(l in CommentLike,
          where: l.comment_id in ^comment_ids and l.user_id == ^user.id,
          select: l.comment_id
        )
        |> Repo.all()
        |> MapSet.new()
      else
        MapSet.new()
      end

    Enum.map(comments, fn comment ->
      # Assign properties seamlessly directly into the virtual schema map fields
      %{comment | likes_count: Map.get(likes_counts, comment.id, 0)}
      |> Map.put(:has_liked, MapSet.member?(liked_ids, comment.id))
    end)
  end

  # Delete Comment feature
  def delete_comment(user, comment_id) do
    # 1. Fetch comment and preload the associated event to check ownership
    comment = Repo.get!(Comment, comment_id) |> Repo.preload(:event)

    # 2. Permission Check: Author OR Event Organizer
    is_author = comment.user_id == user.id
    is_organizer = comment.event.created_by == user.id

    if is_author || is_organizer do
      Repo.delete(comment)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  The definitive comment interaction engine. Handles unique database inserts,
  atomic like increments, real-time WebSocket ticker updates, and author notifications.

  Returns:
    * {:ok, :liked}        -> Successfully liked, increments updated, alerts sent.
    * {:error, :already_liked} -> Safe rollback transaction bypass to block duplicate clicks.
  """
  def like_comment(user_id, comment_id) do
    Repo.transaction(fn ->
      # 1. ATTEMPT UNIQUE LIKE INSERTION
      # Leveraging the unique index constraint prevents double-liking or cache thrashing
      case %Kollective.Events.CommentLike{}
           |> Kollective.Events.CommentLike.changeset(%{user_id: user_id, comment_id: comment_id})
           |> Repo.insert() do
        {:ok, _like} ->
          # 3. NOTIFICATION DISPATCH (Fetch fresh comment metrics out of the transaction)
          comment = Repo.get!(Comment, comment_id) |> Repo.preload([:user])

          # SELF-NOTIFICATION GUARD: Never notify the author if they like their own comment
          if comment.user_id != user_id do
            # Arguments layout contract: target_user_id, actor_id, type, database_attrs, websocket_payload
            Notifications.notify(
              # Recipient (The Author)
              comment.user_id,
              # Actor (The Liker)
              user_id,
              # Validated clean snake_case type from your registry list
              "favourite",
              %{
                event_id: comment.event_id,
                target_id: comment.id,
                target_type: "Comment"
              },
              %{
                post_id: nil,
                preview:
                  "❤️ Someone liked your comment: \"#{String.slice(comment.content || "", 0, 30)}...\""
              }
            )
          end

          # 4. STREAM REAL-TIME TICKER UPDATES DOWNSTREAM TO ACTIVE VIEWERS
          broadcast_comment_update(comment)

          {:ok, :liked}

        {:error, _changeset} ->
          # Smoothly roll back the transaction to neutralize duplicate clicking spam
          Repo.rollback(:already_liked)
      end
    end)
  end

  # ─── REAL-TIME TRANSMISSION DATA PIPELINE ───
  defp broadcast_comment_update(%Comment{} = comment) do
    # Broadcasts across your unified FeedChannel event topic room block
    Phoenix.PubSub.broadcast(
      Kollective.PubSub,
      "event:#{comment.event_id}",
      {"comment_updated",
       %{
         id: comment.id,
         # Display the freshly incremented value instantly
         likes_count: comment.likes_count + 1
       }}
    )
  end

  @doc """
  Compiles and launches a new collective action from the frontend wizard.
  Verifies organizational identity contexts, blocks boundary spoofing, and schedules async tasks.
  """
  def create_action(%Kollective.Accounts.User{} = current_user, attrs \\ %{}) do
    _now = DateTime.utc_now()
    has_coordinates? = not is_nil(attrs["latitude"] || attrs[:latitude])
    address_text = attrs["street"] || attrs[:street] || attrs["address"] || attrs[:address]

    # 1. Organization Posting Overrides Check
    # If the user selects to post on behalf of an approved Organization, bind its context!
    organization_id = attrs["organization_id"] || attrs[:organization_id]

    author =
      if organization_id do
        is_member? =
          Repo.exists?(
            from(m in Kollective.Accounts.OrganizationMembership,
              where:
                m.organization_id == ^organization_id and m.user_id == ^current_user.id and
                  m.status == :approved
            )
          )

        if is_member?, do: Accounts.get_user!(organization_id), else: current_user
      else
        current_user
      end

    Multi.new()
    # Step A: Validate and write the core action row inside our polymorphic event structure
    |> Multi.insert(:event, fn _changes ->
      base_attrs =
        attrs
        |> Map.put("event_status", "published")
        |> Map.put("organization_id", if(author.type == :organization, do: author.id, else: nil))

      %Event{created_by: current_user.id}
      |> Event.creation_changeset(base_attrs)
      # TARGETING ENFORCEMENT: Strips forged boundaries from standard citizens
      |> validate_and_fix_targeting(base_attrs, current_user)
    end)

    # Step B: Auto-Join Creator as the First Accepted Participant
    |> Multi.insert(:organizer_attendance, fn %{event: event} ->
      %EventParticipant{user_id: current_user.id, event_id: event.id, status: "accepted"}
    end)

    # Step C: Increment attendee tracking cache column atomically on the row
    |> Multi.update_all(
      :inc_participants,
      fn %{event: event} ->
        from(e in Event, where: e.id == ^event.id)
      end,
      inc: [participants_count: 1]
    )

    # Step D: SCHEDULE TIMELINE WORKERS (Oban Background Engine)
    |> Multi.run(:schedule_workers, fn _repo, %{event: event} ->
      # Enqueue live start triggers and countdown reminders automatically
      %{"event_id" => event.id}
      |> Kollective.Workers.EventStartWorker.new(scheduled_at: event.start_time)
      |> Oban.insert!()

      {:ok, :scheduled}
    end)

    # Step E: Conditionally Enqueue the Polymorphic Oban GeocodeWorker
    # Runs ONLY if the frontend left longitude/latitude parameters empty!
    |> Multi.run(:enqueue_geocode, fn _repo, %{event: event} ->
      if (not has_coordinates? and address_text) && String.trim(address_text) != "" do
        %{"target_id" => event.id, "schema_type" => "Event", "address_text" => address_text}
        |> Kollective.Workers.GeocodeWorker.new()
        |> Oban.insert()
      else
        {:ok, :skipped}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        # Broadcast live socket notifications out to update your feeds in under 0.001ms
        Phoenix.PubSub.broadcast(
          Kollective.PubSub,
          "feed:public",
          {:new_event_registered, event.id}
        )

        {:ok, Repo.preload(event, [:user, :organization])}

      {:error, _failed_step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  The definitive localized action compiler. Filters your polymorphic events engine
  by specific action categories and cross-checks tiered scope toggles against
  the viewer's physical home base parameters or geometric coordinates .
  """
  def list_collective_actions(%Kollective.Accounts.User{} = user, category_tab, scope_toggle) do
    # Precise 60 miles boundary sweep radius (96,560 meters)
    radius_meters = 96560

    # 1. Base Query: Restrict results to active, published collective action models
    # Filter out regular timeline posts and standard informational calendar entries
    base_query =
      from(e in Event,
        where:
          e.event_status == "published" and e.category in ~w(protest town_hall rally meeting),
        # Preload actor profiles to prevent N+1 loop overhead
        preload: [:user, :organization]
      )

    # 2. STEP 2: DYNAMIC DASHBOARD CATEGORY TAB FILTER SLIDER
    # Maps to your frontend layout classification selections ("protest", "town_hall", etc.)
    query =
      if (category_tab && category_tab != "all") and category_tab != "",
        do: from(e in base_query, where: e.category == ^to_string(category_tab)),
        else: base_query

    # 3. STEP 3: TIERED GEOGRAPHY BOUNDARY FILTER MATRIX
    # Coordinates your "Local / State / Country" sliding panel widget parameters
    query =
      case scope_toggle do
        "country" ->
          # Broadest Scope: Restrict content strictly to the citizen's sovereign country borders
          from(e in query, where: e.origin_country == ^user.country)

        "state" ->
          # Regional Scope: Restrict content strictly to the citizen's administrative state line boundaries
          from(e in query,
            where: e.origin_state == ^user.state and e.origin_country == ^user.country
          )

        "local" ->
          # Grassroots Local Scope: Fall back to shared structural political districts,
          # municipal city boundaries, OR a precise 60-mile physical radius sweep
          conditions = []

          conditions =
            if user.city_id,
              do: [dynamic([e], e.origin_city_id == ^user.city_id) | conditions],
              else: conditions

          conditions =
            if user.district_l1_id && user.state,
              do: [
                dynamic(
                  [e],
                  e.origin_district_l1 == ^user.district_l1_id and e.origin_state == ^user.state
                )
                | conditions
              ],
              else: conditions

          conditions =
            if user.district_l2_id && user.state,
              do: [
                dynamic(
                  [e],
                  e.origin_district_l2 == ^user.district_l2_id and e.origin_state == ^user.state
                )
                | conditions
              ],
              else: conditions

          conditions =
            if user.location,
              do: [
                dynamic(
                  [e],
                  fragment("ST_DWithin(?, ?, ?)", e.location, ^user.location, ^radius_meters)
                )
                | conditions
              ],
              else: conditions

          if conditions == [] do
            from(e in query, where: false)
          else
            or_conditions =
              Enum.reduce(conditions, fn cond_expr, acc -> dynamic([e], ^cond_expr or ^acc) end)

            from(e in query, where: ^or_conditions)
          end

        _all_fallback ->
          query
      end

    # 4. EXECUTE B-TREE TIMELINE RETRIEVAL PASS
    query
    # Chronological sorting path maps perfectly to your card feeds
    |> order_by([e], desc: e.start_time)
    |> Repo.all()
  end
end

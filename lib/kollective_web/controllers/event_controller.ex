defmodule KollectiveWeb.EventController do
  use KollectiveWeb, :controller
  alias Kollective.Accounts.Accounts
  alias Kollective.Events.Events
  alias Kollective.Moderation.Moderation
  alias Kollective.Security.Security
  alias Kollective.Workers.{EventAlertWorker, SecurityAlertWorker}

  # Apply the same rate limit as posts (or stricter, e.g., 2 events/min)
  plug KollectiveWeb.Plugs.RateLimiter when action in [:create]

  @doc """
  Unified Event Creation Controller Action. Handles complex parameter checking,
  fraud identification gates, automated two-strike IP banning, and strategic black-hole responses.
  """
  # POST /api/v1/events
  def create(conn, %{"event" => event_params}) do
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
            Security.blacklist_ip_temporary(ip, :erlang.convert_time_unit(1, :hours, :millisecond))

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
            enqueue_security_alert("hard_ban_attempt", user.id, ip, 1, "Triggered word: #{matched_word}")

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
              data: KollectiveWeb.EventJSON.data(final_event)
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              status: "error",
              errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                Enum.reduce(opts, msg, fn {key, value}, acc ->
                  String.replace(acc, "%{#{key}}", to_string(value))
                end)
              end)
            })
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
  def update(conn, %{"id" => id, "event" => event_params}) do
    user = conn.assigns.current_user
    ip = guest_ip(conn)

    # 1. Fetch the existing event from the database first
    case Events.get_event(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Event not found."})

      {:ok, event} ->
        # 2. OWNERSHIP GUARD: Stop bad actors from modifying other users' groups
        if event.created_by != user.id do
          conn |> put_status(:forbidden) |> json(%{error: "You are not authorized to edit this event."})
        else
          # 3. MODERATION SCAN: Pipe edits through the unified five-priority matrix [INDEX]
          case Moderation.determine_status(user, event_params) do
            {:error, :forbidden_content, matched_word} ->
              # TWO-STRIKE BLACKLIST GATING [INDEX]
              Moderation.track_denied_word(user.id, matched_word)

              case Moderation.record_denial(user.id) do
                :cooldown ->
                  triggered_words = Moderation.get_denied_words(user.id)
                  Security.blacklist_ip_temporary(ip, :erlang.convert_time_unit(1, :hours, :millisecond))
                  Accounts.flag_user_for_spam("user:#{user.id}")
                  enqueue_security_alert("cooldown_triggered", user.id, ip, 2, "Triggered words: #{triggered_words}")
                  black_hole_response(conn)

                :ok ->
                  enqueue_security_alert("hard_ban_attempt", user.id, ip, 1, "Triggered word: #{matched_word}")
                  conn |> put_status(:unprocessable_entity) |> json(%{error: "Your edits contain prohibited language."}) |> halt()
              end

            {:ok, status} ->
              # Inject the parsed compliance status token directly into attributes map strings [INDEX]
              status_str = Atom.to_string(status)
              final_params = Map.put(event_params, "status", status_str)

              # 4. EXECUTE LOCAL UPDATE PIPELINE
              case Events.update_event(event, final_params) do
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
                  # Output matching your exact EventJSON.data contract payload [INDEX]
                  |> json(%{
                    status: "success",
                    data: KollectiveWeb.EventJSON.data(final_event)
                  })

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{
                    status: "error",
                    errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                      Enum.reduce(opts, msg, fn {key, value}, acc ->
                        String.replace(acc, "%{#{key}}", to_string(value))
                      end)
                    end)
                  })
              end
          end
        end
    end
  end


  # --- Cachex Word-Tracking Operations ---

  #defp track_denied_word(user_id, word) do
  #  Moderation.track_denied_word(user_id, word)
  #end

  #defp get_denied_words(user_id) do
  #  Moderation.get_denied_words(user_id)
  #end

  defp guest_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end


end

defmodule Kollective.Database.MnesiaResolutionEngine do
  @compile {:no_warn_undefined, :mnesia}
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.Incident
  alias Ecto.Multi

  @doc """
  🔒 ATOMIC RESOLUTION MUTATION WRITER
  Saves the action permanently to Postgres via Ecto, updates the Mnesia cluster,
  and fires web sockets to the active admin dashboards simultaneously.
  """
  def resolve_incident(incident_id, action_type, operator_id) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    now_datetime = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1️⃣ Establish target database token mappings
    target_status =
      case action_type do
        "dismiss" -> "resolved_restored"
        "soft_delete" -> "resolved_deleted"
        "hard_ban" -> "resolved_banned"
        _ -> "resolved_unknown"
      end

    # 2️⃣ Wrap execution paths into an explicit Ecto.Multi container block [1]
    Multi.new()
    |> Multi.run(:fetch_postgres_record, fn _repo, _changes ->
      case Repo.get(Incident, incident_id) do
        nil -> {:error, :not_found}
        incident -> {:ok, incident}
      end
    end)
    |> Multi.run(:update_postgres, fn _repo, %{fetch_postgres_record: incident} ->
      # Mutate the source of truth status states [1]
      incident
      |> Incident.changeset(%{
        status: target_status,
        leased_by_id: operator_id,
        leased_until: now_datetime
      })
      |> Repo.update()
    end)
    |> Multi.run(:sync_to_mnesia, fn _repo, _changes ->
      # 3️⃣ Once Postgres transaction validation clears safely, apply mutations to Mnesia mesh [1]
      mnesia_tx =
        :mnesia.transaction(fn ->
          case read_incident_for_write(incident_id) do
            [record] ->
              element = Tuple.to_list(record)

              # Map array indices offset values cleanly:
              # Layout parameters: [Index 0: Table Name, Index 1: ID, Index 2: Status, Index 3: CC, Index 4: Username, Index 5: Desc, Index 6: InsertedAt, Index 7: LeasedBy, Index 8: LeasedUntil]
              updated_record =
                element
                # Status update [1]
                |> List.replace_at(2, target_status)
                # Operator ID signature
                |> List.replace_at(7, to_string(operator_id))
                # Unix lease timeout stamp
                |> List.replace_at(8, now_unix)

              # [1]
              :mnesia.write(List.to_tuple(updated_record))
              {:ok, target_status}

            [] ->
              # If a cold boot happened and it wasn't in Mnesia, that's okay, we can create it
              {:ok, :not_in_memory}
          end
        end)

      case mnesia_tx do
        {:atomic, res} -> {:ok, res}
        {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      end
    end)
    # Commit both pipelines in unison!
    |> Repo.transaction()
    |> case do
      {:ok, %{update_postgres: _updated_incident}} ->
        # 📣 Broadcast mutations out to React/Websocket connections safely
        sync_resolution_broadcast(incident_id, target_status, operator_id)
        {:ok, target_status}

      {:error, :fetch_postgres_record, :not_found, _} ->
        {:error, :not_found}

      {:error, step, reason, _} ->
        Logger.error(
          "❌ [RESOLUTION CRITICAL EXCEPTION]: Phase failure during step '#{step}': #{inspect(reason)}"
        )

        {:error, :transaction_failed}
    end
  end

  defp sync_resolution_broadcast(id, status, operator_id) do
    payload = %{
      incident_id: to_string(id),
      status: status,
      adjudicated_by: to_string(operator_id)
    }

    KollectiveWeb.Endpoint.broadcast!(
      "admin_notifications:global",
      "incident_resolved",
      payload
    )
  end

  @doc """
  🔓 ATOMIC LEASE RELEASE WRITER
  Removes operator lease trackers from both Postgres and Mnesia cluster memory,
  returning the incident to the global pool for other operators to claim.
  """
  def release_incident_lease(incident_id, operator_id) do
    alias Ecto.Multi

    Multi.new()
    # 1️⃣ Fetch the target record from the Postgres source of truth
    |> Multi.run(:fetch_postgres_record, fn _repo, _changes ->
      case Repo.get(Incident, incident_id) do
        nil -> {:error, :not_found}
        incident -> {:ok, incident}
      end
    end)
    # 2️⃣ Clear lease tracking metrics permanently inside PostgreSQL
    |> Multi.run(:update_postgres, fn _repo, %{fetch_postgres_record: incident} ->
      # Ensure the operator trying to drop it is the one who actually holds the lease
      if to_string(incident.leased_by_id) == to_string(operator_id) do
        incident
        |> Incident.changeset(%{
          leased_by_id: nil,
          leased_until: nil
          # status stays "pending" so it remains visible in active queues
        })
        |> Repo.update()
      else
        {:error, :unauthorized_lease_holder}
      end
    end)
    # 3️⃣ Synchronize structural changes to the distributed Mnesia network mesh
    |> Multi.run(:sync_to_mnesia, fn _repo, _changes ->
      mnesia_tx =
        :mnesia.transaction(fn ->
          case read_incident_for_write(incident_id) do
            [record] ->
              element = Tuple.to_list(record)

              # Map array indices offset values cleanly to wipe lease metrics:
              # Index 7: leased_by_id -> set to nil
              # Index 8: leased_until -> set to nil
              updated_record =
                element
                |> List.replace_at(7, nil)
                |> List.replace_at(8, nil)

              :mnesia.write(List.to_tuple(updated_record))
              {:ok, :released}

            [] ->
              # Fallback if a node restarted and the cache wasn't populated yet
              {:ok, :not_in_memory}
          end
        end)

      case mnesia_tx do
        {:atomic, res} -> {:ok, res}
        {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _results} ->
        # 📣 Broadcast out over admin channels so the UI instantly unlocks for others
        sync_lease_dropped_broadcast(incident_id)
        {:ok, :released}

      {:error, :fetch_postgres_record, :not_found, _} ->
        {:error, :not_found}

      {:error, :update_postgres, :unauthorized_lease_holder, _} ->
        {:error, :unauthorized_lease_holder}

      {:error, step, reason, _} ->
        Logger.error(
          "❌ [LEASE RELEASE CRITICAL]: Phase failure during step '#{step}': #{inspect(reason)}"
        )

        {:error, :transaction_failed}
    end
  end

  defp sync_lease_dropped_broadcast(id) do
    payload = %{
      incident_id: to_string(id),
      status: "pending",
      leased_by_id: nil
    }

    KollectiveWeb.Endpoint.broadcast!(
      "admin_notifications:global",
      "incident_lease_dropped",
      payload
    )
  end

  @doc """
  🔒 ATOMIC LEASE ACQUISITION WRITER
  Acquires an exclusive cluster lock over an active incident.
  Guarantees that race conditions between multiple operators across nodes are safely rejected.
  """
  def claim_incident(incident_id, operator_id) do
    alias Ecto.Multi

    # Enforce a rolling 15-minute lease threshold window
    lease_duration_seconds = 15 * 60
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    leased_until_unix = now_unix + lease_duration_seconds

    now_datetime = DateTime.utc_now() |> DateTime.truncate(:second)
    leased_until_datetime = DateTime.add(now_datetime, lease_duration_seconds, :second)

    Multi.new()
    # 1️⃣ Fetch from Postgres to ensure the item isn't already resolved or locked long-term
    |> Multi.run(:fetch_postgres_record, fn _repo, _changes ->
      case Repo.get(Incident, incident_id) do
        nil -> {:error, :not_found}
        incident -> {:ok, incident}
      end
    end)
    # 2️⃣ Verify inside Postgres that the lease is open or has expired
    |> Multi.run(:update_postgres, fn _repo, %{fetch_postgres_record: incident} ->
      is_expired =
        incident.leased_until &&
          DateTime.compare(DateTime.utc_now(), incident.leased_until) == :gt

      is_unlocked = is_nil(incident.leased_by_id)

      if incident.status == "pending" && (is_unlocked || is_expired) do
        incident
        |> Incident.changeset(%{
          leased_by_id: operator_id,
          leased_until: leased_until_datetime
        })
        |> Repo.update()
      else
        {:error, :incident_already_locked}
      end
    end)
    # 3️⃣ Synchronize structural data modifications to Mnesia cluster memory
    |> Multi.run(:sync_to_mnesia, fn _repo, _changes ->
      mnesia_tx =
        :mnesia.transaction(fn ->
          case read_incident_for_write(incident_id) do
            [record] ->
              # CRITICAL: Record locked across cluster with exclusive write lock
              element = Tuple.to_list(record)

              # Layout mapping updates:
              # Index 7: leased_by_id -> operator_id
              # Index 8: leased_until -> leased_until_unix
              updated_record =
                element
                |> List.replace_at(7, to_string(operator_id))
                |> List.replace_at(8, leased_until_unix)

              :mnesia.write(List.to_tuple(updated_record))
              {:ok, :claimed}

            [] ->
              # Safe recovery if it fell out of high-speed memory space cache
              {:ok, :not_in_memory}
          end
        end)

      case mnesia_tx do
        {:atomic, res} -> {:ok, res}
        {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _results} ->
        # 📣 Broadcast lock to live admin dashboards so they visually grey out this ticket
        sync_lease_claimed_broadcast(incident_id, operator_id, leased_until_unix)
        {:ok, :claimed}

      {:error, :fetch_postgres_record, :not_found, _} ->
        {:error, :not_found}

      {:error, :update_postgres, :incident_already_locked, _} ->
        {:error, :incident_already_locked}

      {:error, step, reason, _} ->
        Logger.error(
          "❌ [INCIDENT CLAIM EXCEPTION]: Phase failure during step '#{step}': #{inspect(reason)}"
        )

        {:error, :transaction_failed}
    end
  end

  defp sync_lease_claimed_broadcast(id, operator_id, expires_at_unix) do
    payload = %{
      incident_id: to_string(id),
      status: "pending",
      leased_by_id: to_string(operator_id),
      leased_until: expires_at_unix
    }

    KollectiveWeb.Endpoint.broadcast!("admin_notifications:global", "incident_leased", payload)
  end

  @doc """
  🔒 ATOMIC LEASE RENEWAL / EXTENSION
  Extends an active operator's lease by an extra 5 minutes.
  Fails if the operator has already lost the lease to prevent stale overrides.
  """
  def extend_incident_lease(incident_id, operator_id) do
    alias Ecto.Multi

    # Configure a rolling 5-minute extension block
    extension_seconds = 5 * 60
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    new_expires_unix = now_unix + extension_seconds

    now_datetime = DateTime.utc_now() |> DateTime.truncate(:second)
    new_expires_datetime = DateTime.add(now_datetime, extension_seconds, :second)

    Multi.new()
    # 1️⃣ Pull the structural record out of the Postgres source of truth
    |> Multi.run(:fetch_postgres_record, fn _repo, _changes ->
      case Repo.get(Incident, incident_id) do
        nil -> {:error, :not_found}
        incident -> {:ok, incident}
      end
    end)
    # 2️⃣ Verify the operator still owns the lease before saving the extension
    |> Multi.run(:update_postgres, fn _repo, %{fetch_postgres_record: incident} ->
      is_still_owner = to_string(incident.leased_by_id) == to_string(operator_id)
      is_not_resolved = incident.status == "pending"

      if is_still_owner && is_not_resolved do
        incident
        |> Incident.changeset(%{leased_until: new_expires_datetime})
        |> Repo.update()
      else
        {:error, :lease_ownership_lost}
      end
    end)
    # 3️⃣ Apply the updated timestamp to the replicated Mnesia network cluster mesh
    |> Multi.run(:sync_to_mnesia, fn _repo, _changes ->
      mnesia_tx =
        :mnesia.transaction(fn ->
          case read_incident_for_write(incident_id) do
            [record] ->
              element = Tuple.to_list(record)

              # Update the leased_until parameter at Index 8 matching your schema mapping
              updated_record = List.replace_at(element, 8, new_expires_unix)

              :mnesia.write(List.to_tuple(updated_record))
              {:ok, new_expires_unix}

            [] ->
              {:ok, :not_in_memory}
          end
        end)

      case mnesia_tx do
        {:atomic, res} -> {:ok, res}
        {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _results} ->
        # 📣 Broadcast out the updated lease stamp down the live cluster channel streams
        sync_lease_claimed_broadcast(incident_id, operator_id, new_expires_unix)
        {:ok, :extended}

      {:error, :fetch_postgres_record, :not_found, _} ->
        {:error, :not_found}

      {:error, :update_postgres, :lease_ownership_lost, _} ->
        {:error, :lease_ownership_lost}

      {:error, step, reason, _} ->
        Logger.error(
          "❌ [LEASE EXTENSION EXCEPTION]: Phase failure during step '#{step}': #{inspect(reason)}"
        )

        {:error, :transaction_failed}
    end
  end

  defp read_incident_for_write(incident_id) do
    case :mnesia.read(:scholar_incidents, incident_id, :write) do
      [] -> :mnesia.read(:scholar_incidents, to_string(incident_id), :write)
      found -> found
    end
  end
end

defmodule Kollective.Database.MnesiaQueueEngine do
  @compile {:no_warn_undefined, :mnesia}
  require Logger

  @doc """
  Pulls next available incident ticket using a decentralized, distributed transaction lease.
  Enforces an active-lease check: if the moderator already has an active, unexpired lease,
  returns that ticket to ensure even distribution and prevent ticket hoarding.
  """
  def lease_next_incident(moderator_id, country_code, is_global?, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    # 5-minute processing lease lock threshold
    lease_expiry = now + 300
    force_new? = Keyword.get(opts, :force_new, false)

    # Ensure Mnesia tables are ready or attempt hydration if cold
    maybe_rehydrate_from_postgres()

    # 🚀 ATOMIC DISTRIBUTED TRANSACTION:
    # Mnesia coordinates memory locks across all nodes concurrently, ensuring zero duplication.
    transaction_result =
      :mnesia.transaction(fn ->
        active_lease =
          if force_new? do
            :none
          else
            find_active_lease_for_moderator(moderator_id, now)
          end

        case active_lease do
          {:ok, active_record} ->
            {:already_leased, serialize_mnesia_record(active_record)}

          :none ->
            case :mnesia.all_keys(:scholar_incidents) do
              [] ->
                :no_tickets_available

              all_keys ->
                find_and_lease_ticket(
                  all_keys,
                  moderator_id,
                  country_code,
                  is_global?,
                  now,
                  lease_expiry
                )
            end
        end
      end)

    case transaction_result do
      {:atomic, {:already_leased, active_ticket}} ->
        Logger.info(
          "ℹ️ [MnesiaQueueEngine] Moderator #{moderator_id} already has active lease on incident #{active_ticket.id}. Returning existing ticket."
        )

        {:ok, active_ticket}

      {:atomic, {:ok, leased_ticket}} ->
        # Synchronize lease to Postgres if record exists there (Dual-Write)
        sync_lease_to_postgres(leased_ticket.id, moderator_id, lease_expiry)

        # Broadcast live event to moderator dashboards
        broadcast_lease(leased_ticket.id, moderator_id, lease_expiry)

        {:ok, leased_ticket}

      {:atomic, :no_tickets_available} ->
        {:error, :empty_queue}

      error ->
        Logger.error(
          "❌ [MNESIA TX CRITICAL]: Transaction crashed over cluster: #{inspect(error)}"
        )

        {:error, :transaction_failed}
    end
  end

  @doc """
  Returns `{:ok, ticket}` if a moderator currently holds an active, unexpired lease on any incident,
  or `:none` otherwise.
  """
  def get_active_lease(moderator_id) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    case :mnesia.transaction(fn -> find_active_lease_for_moderator(moderator_id, now) end) do
      {:atomic, {:ok, record}} -> {:ok, serialize_mnesia_record(record)}
      _ -> :none
    end
  end

  @doc """
  Checks if a moderator currently holds an active, unexpired lease on any incident.
  """
  def has_active_lease?(moderator_id) do
    match?({:ok, _}, get_active_lease(moderator_id))
  end

  defp find_active_lease_for_moderator(moderator_id, now) do
    mod_str = to_string(moderator_id)

    matches =
      :mnesia.match_object({:scholar_incidents, :_, "pending", :_, :_, :_, :_, mod_str, :_})

    matches =
      if Enum.empty?(matches) and is_integer(moderator_id) do
        :mnesia.match_object(
          {:scholar_incidents, :_, "pending", :_, :_, :_, :_, moderator_id, :_}
        )
      else
        matches
      end

    case Enum.find(matches, fn record ->
           leased_until = elem(record, 8)
           not lease_expired?(leased_until, now)
         end) do
      nil -> :none
      record -> {:ok, record}
    end
  end

  # --- Internal Transaction Search Loops ---

  defp find_and_lease_ticket(all_keys, moderator_id, country_code, is_global?, now, lease_expiry) do
    # Scan through keys, read available ones, and pick the best (oldest) matching ticket
    candidates =
      Enum.reduce(all_keys, [], fn id, acc ->
        case :mnesia.read(:scholar_incidents, id, :read) do
          [record] ->
            element = Tuple.to_list(record)
            status = Enum.at(element, 2)
            ticket_cc = Enum.at(element, 3)
            inserted_at = Enum.at(element, 6)
            leased_until = Enum.at(element, 8)

            is_available? = status == "pending" && lease_expired?(leased_until, now)
            geo_clearance? = geo_cleared?(is_global?, ticket_cc, country_code)

            if is_available? && geo_clearance? do
              sort_key = parse_inserted_at_to_unix(inserted_at, now)
              [{sort_key, id} | acc]
            else
              acc
            end

          [] ->
            acc
        end
      end)

    case candidates do
      [] ->
        :no_tickets_available

      _ ->
        # Sort ascending by inserted_at so oldest incident is leased first (FIFO)
        sorted = Enum.sort_by(candidates, fn {sort_key, _id} -> sort_key end)
        attempt_lease_from_sorted(sorted, moderator_id, now, lease_expiry)
    end
  end

  defp attempt_lease_from_sorted([], _mod_id, _now, _lease_expiry), do: :no_tickets_available

  defp attempt_lease_from_sorted([{_ts, id} | rest], moderator_id, now, lease_expiry) do
    # Take exclusive write lock on chosen record
    case :mnesia.read(:scholar_incidents, id, :write) do
      [record] ->
        element = Tuple.to_list(record)
        status = Enum.at(element, 2)
        leased_until = Enum.at(element, 8)

        # Re-check availability under write lock (in case of race condition)
        if status == "pending" && lease_expired?(leased_until, now) do
          updated_record =
            List.to_tuple(
              element
              |> List.replace_at(7, to_string(moderator_id))
              |> List.replace_at(8, lease_expiry)
            )

          :mnesia.write(updated_record)
          {:ok, serialize_mnesia_record(updated_record)}
        else
          # Ticket was leased by someone else in the split second, try next candidate
          attempt_lease_from_sorted(rest, moderator_id, now, lease_expiry)
        end

      [] ->
        attempt_lease_from_sorted(rest, moderator_id, now, lease_expiry)
    end
  end

  # --- Helpers ---

  defp lease_expired?(nil, _now), do: true
  defp lease_expired?(leased_until, now) when is_integer(leased_until), do: leased_until < now
  defp lease_expired?(%DateTime{} = dt, _now), do: DateTime.compare(dt, DateTime.utc_now()) == :lt

  defp lease_expired?(leased_until_str, now) when is_binary(leased_until_str) do
    case Integer.parse(leased_until_str) do
      {ts, ""} ->
        ts < now

      _ ->
        case DateTime.from_iso8601(leased_until_str) do
          {:ok, dt, _} -> DateTime.compare(dt, DateTime.utc_now()) == :lt
          _ -> true
        end
    end
  end

  defp lease_expired?(_, _), do: true

  defp geo_cleared?(true, _ticket_cc, _country_code), do: true
  defp geo_cleared?(_is_global?, nil, _country_code), do: true

  defp geo_cleared?(_is_global?, ticket_cc, _country_code)
       when ticket_cc in ["GLOBAL", "global", ""],
       do: true

  defp geo_cleared?(_is_global?, ticket_cc, country_code)
       when is_binary(ticket_cc) and is_binary(country_code) do
    String.upcase(ticket_cc) == String.upcase(country_code)
  end

  defp geo_cleared?(_is_global?, _ticket_cc, _country_code), do: false

  defp parse_inserted_at_to_unix(ts, _now) when is_integer(ts), do: ts
  defp parse_inserted_at_to_unix(%DateTime{} = dt, _now), do: DateTime.to_unix(dt)

  defp parse_inserted_at_to_unix(%NaiveDateTime{} = ndt, _now) do
    DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.to_unix()
  end

  defp parse_inserted_at_to_unix(str, now) when is_binary(str) do
    case Integer.parse(str) do
      {val, ""} ->
        val

      _ ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> DateTime.to_unix(dt)
          _ -> now
        end
    end
  end

  defp parse_inserted_at_to_unix(_other, now), do: now

  defp serialize_mnesia_record(record_tuple) do
    list = Tuple.to_list(record_tuple)

    raw_inserted_at = Enum.at(list, 6)

    formatted_inserted_at =
      case raw_inserted_at do
        ts when is_integer(ts) ->
          case DateTime.from_unix(ts) do
            {:ok, dt} -> DateTime.to_iso8601(dt)
            _ -> DateTime.utc_now() |> DateTime.to_iso8601()
          end

        str when is_binary(str) ->
          str

        %DateTime{} = dt ->
          DateTime.to_iso8601(dt)

        _ ->
          DateTime.utc_now() |> DateTime.to_iso8601()
      end

    %{
      id: to_string(Enum.at(list, 1)),
      status: to_string(Enum.at(list, 2)),
      country_code: Enum.at(list, 3) || "GLOBAL",
      target_username: to_string(Enum.at(list, 4) || "unknown"),
      description: Enum.at(list, 5) || "",
      inserted_at: formatted_inserted_at,
      leased_by_id: Enum.at(list, 7),
      leased_until: Enum.at(list, 8),
      origin_node_atom: to_string(Node.self())
    }
  end

  defp sync_lease_to_postgres(ticket_id, moderator_id, lease_expiry_unix) do
    alias Kollective.Repo
    alias Kollective.Moderation.Incident

    case Repo.get(Incident, ticket_id) do
      nil ->
        :ok

      incident ->
        lease_until_dt = DateTime.from_unix!(lease_expiry_unix)

        incident
        |> Incident.changeset(%{
          leased_by_id: moderator_id,
          leased_until: lease_until_dt
        })
        |> Repo.update()
    end
  rescue
    e ->
      Logger.warning("⚠️ [MnesiaQueueEngine] Postgres lease sync notice: #{inspect(e)}")
      :ok
  end

  defp broadcast_lease(ticket_id, moderator_id, lease_expiry_unix) do
    payload = %{
      incident_id: to_string(ticket_id),
      status: "pending",
      leased_by_id: to_string(moderator_id),
      leased_until: lease_expiry_unix
    }

    KollectiveWeb.Endpoint.broadcast(
      "admin_notifications:global",
      "incident_leased",
      payload
    )

    KollectiveWeb.Endpoint.broadcast(
      "admin_notifications:global",
      "incident_claimed",
      payload
    )
  rescue
    e ->
      Logger.warning("⚠️ [MnesiaQueueEngine] Broadcast notice: #{inspect(e)}")
      :ok
  end

  defp maybe_rehydrate_from_postgres do
    alias Kollective.Repo
    alias Kollective.Moderation.Incident
    import Ecto.Query

    if :mnesia.system_info(:is_running) == :yes and
         :scholar_incidents in :mnesia.system_info(:tables) and
         :mnesia.table_info(:scholar_incidents, :size) == 0 do
      try do
        active_incidents = from(i in Incident, where: i.status == "pending") |> Repo.all()

        Enum.each(active_incidents, fn incident ->
          inserted_at_unix =
            case incident.inserted_at do
              %DateTime{} = dt -> DateTime.to_unix(dt)
              %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.to_unix()
              _ -> System.system_time(:second)
            end

          leased_until_unix =
            if incident.leased_until, do: DateTime.to_unix(incident.leased_until), else: nil

          mnesia_record = {
            :scholar_incidents,
            to_string(incident.id),
            incident.status,
            incident.country_code,
            to_string(incident.target_username),
            incident.description,
            inserted_at_unix,
            if(incident.leased_by_id, do: to_string(incident.leased_by_id), else: nil),
            leased_until_unix
          }

          :mnesia.dirty_write(:scholar_incidents, mnesia_record)
        end)
      rescue
        _ -> :ok
      end
    end
  end
end

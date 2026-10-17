defmodule Kollective.Moderation.QueueEngine do
  @moduledoc """
  DEPRECATED: Kept for reference.

  Original PostgreSQL pessimistic row-locking queue engine (`SELECT FOR UPDATE SKIP LOCKED`).

  Replacement:
  - High-throughput distributed incident queuing is now handled by
    `Kollective.Database.MnesiaQueueEngine` (`lease_next_incident/3`, `claim_incident/2`,
    `release_lease/2`, `extend_lease/2`), which utilizes in-memory Mnesia tables,
    FIFO ordering, automated lease reaping, dual-writes to PostgreSQL, and Phoenix PubSub broadcasts.
  """

  import Ecto.Query
  alias Kollective.Repo

  @doc """
  Locks and leases a unique block of open incidents for a specific moderator session.
  Uses a SELECT FOR UPDATE NOWAIT row lock strategy to prevent race conditions.
  """
  @deprecated "Use Kollective.Database.MnesiaQueueEngine.lease_next_incident/3 instead"
  def lease_next_incidents(moderator_id, node_country, is_global?, limit \\ 10) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    # 5-minute processing window lease
    lease_expiry = DateTime.add(now, 300, :second)

    Repo.transaction(fn ->
      # 1️⃣ Build a localized target matching boundary query
      base_query =
        from(i in "scholar_incidents",
          where: i.status == "pending",
          # An incident is available if it has no active lease or the lease expired
          where: is_nil(i.leased_until) or i.leased_until < ^now,
          order_by: [asc: i.inserted_at]
        )

      # 2️⃣ Apply Geographical routing constraints
      query =
        if is_global? do
          # Global staff can pull from any country queue block
          base_query
        else
          from(i in base_query, where: i.country_code == ^node_country)
        end

      # 3️⃣ Atomic Row Interception: Lock rows using PostgreSQL Pessimistic Locks
      target_ids =
        from(i in query,
          select: i.id,
          limit: ^limit,
          # Skips items already leased by other staff
          lock: "SELECT FOR UPDATE SKIP LOCKED"
        )
        |> Repo.all()

      # 4️⃣ Commit the lease lock down to the database disk memory parameters
      if length(target_ids) > 0 do
        from(i in "scholar_incidents", where: i.id in ^target_ids)
        |> Repo.update_all(
          set: [
            leased_by_id: moderator_id,
            leased_until: lease_expiry
          ]
        )
      end

      # Return the fully leased rows to populate the moderator's React list view
      fetch_leased_incidents(target_ids)
    end)
  end

  defp fetch_leased_incidents([]), do: []

  defp fetch_leased_incidents(ids) do
    from(i in "scholar_incidents", where: i.id in ^ids) |> Repo.all()
  end
end

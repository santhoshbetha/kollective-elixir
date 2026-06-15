#Ecto Migration to ensure your events table is correctly indexed for these ULID district lookups

defmodule Kollective.Repo.Migrations.AddUlidIndexesToEvent do
  use Ecto.Migration

  def change do
    # 1. Primary Index for Recursive CTEs
    # A composite index on [parent_id, id] is critical for the "Walk Down"
    # logic used to find all sub-districts in a State or National feed.
    create index(:political_districts, [:parent_id, :id])

    # 2. Localized Event Lookup
    # Standard index for finding events directly by their district ULID.
    create index(:events, [:origin_district_id])

    # 3. High-Performance Combined Filter
    # If your feed often filters by 'status' (published) and 'district',
    # use a composite index to avoid scanning rejected/pending events.
    create index(:events, [:origin_district_id, :event_status])

    # 4. Chronological Sorting
    # Since ULIDs are lexicographically sortable, an index on 'id'
    # already provides a partial time-order, but a dedicated index
    # on [origin_district_id, inserted_at] is best for "Latest Feed" queries.
    create index(:events, [:origin_district_id, :inserted_at])
  end
end

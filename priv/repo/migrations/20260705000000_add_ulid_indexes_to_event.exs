# Ecto Migration to ensure your events table is correctly indexed for these ULID district lookups

defmodule Kollective.Repo.Migrations.AddUlidIndexesToEvent do
  use Ecto.Migration

  def change do
    # 1. Primary Index for Recursive CTEs
    # A composite index on [parent_id, id] is critical for the "Walk Down"
    # logic used to find all sub-districts in a State or National feed.
    create_if_not_exists(index(:political_districts, [:parent_id, :id]))

    # 2. Localized Event Lookups (Separate indexes for your 3 levels)
    # Standard index for finding events directly by their district ULID.
    create index(:events, [:origin_district_l1])
    create index(:events, [:origin_district_l2])
    create index(:events, [:origin_district_l3])

    # 3. High-Performance Combined Filters (Location + Status)
    # If your feed often filters by 'status' (published) and 'district',
    # use a composite index to avoid scanning rejected/pending events.
    # This helps instantly load *only published* events for a specific level
    create index(:events, [:origin_district_l1, :event_status])
    create index(:events, [:origin_district_l2, :event_status])
    create index(:events, [:origin_district_l3, :event_status])

    # 4. Chronological Sorting (Location + Time)
    # Since ULIDs are lexicographically sortable, an index on 'id'
    # already provides a partial time-order, but a dedicated index
    # on [origin_district_id, inserted_at] is best for "Latest Feed" queries.
    # This helps optimize "Latest Feed" queries for each specific level
    create index(:events, [:origin_district_l1, :inserted_at])
    create index(:events, [:origin_district_l2, :inserted_at])
    create index(:events, [:origin_district_l3, :inserted_at])
  end
end

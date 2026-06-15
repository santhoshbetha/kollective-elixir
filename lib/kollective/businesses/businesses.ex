#This query implements your multi-tier visibility: matching any of the user's districts
# OR falling within 60 miles (approx. 96,560 meters).

defmodule Kollective.Businesses do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Businesses.{Business, Comment, Upvote}

  def list_local_discovery(user, type) do
    radius_meters = 96560 # 60 miles

    query = from b in Business,
      where: b.type == ^type,
      where: (
        b.origin_city_id == ^user.city_id or
        (b.origin_state_district == ^user.state_district and b.origin_state == ^user.state) or
        (b.origin_state_senate_district == ^user.state_senate_district and b.origin_state == ^user.state) or
        (b.origin_federal_district == ^user.federal_district and b.origin_state == ^user.state) or
        fragment("ST_DWithin(?, ?, ?)", b.location, ^user.location, ^radius_meters)
      )

    # STRATEGY:
    # Proposals: Show all (unverified ideas)
    # Existing: ONLY show those that passed "Business Verification"
    query = if type == :existing do
      where(query, [b], b.verification_status == :verified)
    else
      query
    end

    query
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def upvote_business(user_id, business_id) do
    %Upvote{}
    |> Ecto.Changeset.change(%{user_id: user_id, business_id: business_id})
    # Handles "un-upvote" if clicked again
    |> Repo.insert(on_conflict: :delete_all, conflict_target: [:user_id, :business_id])
  end

  def get_discussion(business_id) do
    from(c in Comment,
      where: c.business_id == ^business_id and is_nil(c.parent_id),
      preload: [:user, [replies: :user]],
      order_by: [asc: c.inserted_at]
    )
    |> Repo.all()
  end

  #"Top Proposals" Leaderboard
  def list_top_proposals(user, limit \\ 5) do
    # Only look at engagement from the last 30 days
    since = DateTime.add(DateTime.utc_now(), -30, :day)

    from b in Business,
      join: u in assoc(b, :upvotes),
      where: b.type == :proposal,
      # Filter by the user's specific Federal District
      where: b.origin_federal_district == ^user.federal_district and b.origin_state == ^user.state,
      where: u.inserted_at > ^since,
      group_by: b.id,
      # Select the business and the count of unique upvotes
      select: %{
        business: b,
        upvote_count: count(u.user_id)
      },
      order_by: [desc: count(u.user_id)],
      limit: ^limit,
      preload: [:user]
  end

  #modify the list_local_discovery function to accept an optional category filter.
  #This allows your React tabs to show "All" or just "Food & Beverage."
  def list_local_discovery2(user, type, opts \\ []) do
    radius_meters = 96560 # 60 miles
    category = Keyword.get(opts, :category)

    query = from b in Business,
      where: b.type == ^type,
      where: (
        b.origin_city_id == ^user.city_id or
        (b.origin_state_district == ^user.state_district and b.origin_state == ^user.state) or
        (b.origin_state_senate_district == ^user.state_senate_district and b.origin_state == ^user.state) or
        (b.origin_federal_district == ^user.federal_district and b.origin_state == ^user.state) or
        fragment("ST_DWithin(?, ?, ?)", b.location, ^user.location, ^radius_meters)
      )

    # Apply category filter if the user selected one in React
    query = if category, do: where(query, [b], b.category == ^category), else: query

    # Ensure existing businesses are verified
    query = if type == :existing, do: where(query, [b], b.verification_status == :verified), else: query

    query
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  # "District Filter" dropdown at the top of the page, so users can toggle between seeing everything in their
  #60-mile radius vs. only businesses in their specific State Senate or Federal District

  #1. modify the query to handle a scope parameter. If the user selects a specific district, we ignore the 60-mile radius
  #and focus only on that political boundary.
  def list_local_discovery3(user, type, opts \\ []) do
    scope = Keyword.get(opts, :scope, "all") # "all", "federal", "state_senate", "city"
    category = Keyword.get(opts, :category)
    radius_meters = 96560 # 60 miles

    query = from b in Business, where: b.type == ^type

    # --- TIERED FILTERING LOGIC ---
    query = case scope do
      "federal" ->
        where(query, [b], b.origin_federal_district == ^user.federal_district)
      "state_senate" ->
        where(query, [b], b.origin_state_senate_district == ^user.state_senate_district)
      "city" ->
        where(query, [b], b.origin_city_id == ^user.city_id)
      _ ->
        # Default: Broad Discovery (Districts OR 60-mile Radius)
        where(query, [b],
          b.origin_city_id == ^user.city_id or
          b.origin_federal_district == ^user.federal_district or
          fragment("ST_DWithin(?, ?, ?)", b.location, ^user.location, ^radius_meters)
        )
    end

    # Apply existing Category and Verification filters
    query = if category, do: where(query, [b], b.category == ^category), else: query
    query = if type == :existing, do: where(query, [b], b.verification_status == :verified), else: query

    query |> order_by([b], desc: b.inserted_at) |> Repo.all() |> Repo.preload(:user)
  end


end

#4. Implementation Strategy for Tabs
#Your React frontend will call the same endpoint with a tab parameter.

#    Tab: "Idea Proposals": Call list_local_discovery(user, :proposal).
#    Tab: "Local Businesses": Call list_local_discovery(user, :existing).

#5. Why this works for your App

#    Geospatial Precision: Using ST_DWithin on a geography type is highly accurate for large distances like 60 miles because it accounts for the Earth's curvature.
#    District Loyalty: Even if a business is 70 miles away, it will show up if it's in the user's Federal District, maintaining your political discovery theme.
#    Discussion Support: Because these are standard Ecto records, you can easily attach a has_many :comments association to the Business schema so users can "join discussion" as requested.

#3. React Frontend Tabs
#In your React UI, you simply switch the API call:

#    Tab "Business Ideas": fetch('/api/businesses?type=proposal')
#        Result: Users see all local brainstorms and can join the discussion.
#    Tab "Directory": fetch('/api/businesses?type=existing')
#        Result: Users see a curated list of shops that have proven they actually exist in the district.

#4. Why this is the best flow

#    Low Barrier for Ideas: Anyone can post a proposal to their State Senate District to see if neighbors like it.
#    High Trust for Shops: By the time an idea becomes an "Existing Business," the user has likely gone through your Business Verification process.

# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kollective.Repo.insert!(%Kollective.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
# priv/repo/seeds.exs
alias Kollective.Repo
alias Kollective.Accounts.User
alias Kollective.Videos.CandidateVideo
alias Kollective.Campaigns.{ElectionDeadline, DebateEvent, DebateShift}

# =========================================================================
# 👤 1. SEED: ACTIVE WORKING-CLASS CANDIDATE USER
# =========================================================================
# Pre-configure profile attributes to match your app configuration parameters
user =
  case Repo.get_by(User, email: "clara.diaz@work.node") do
    nil ->
      Repo.insert!(%User{
        display_name: "Clara Diaz",
        username: "claradiaz",
        email: "clara.diaz@work.node",
        is_candidate: true,
        is_verified_candidate: true,
        candidate_role: :state_rep,
        city_name: "Austin",
        state: "TX",
        country: "US",
        precinct: "Central Grid Ward B"
      })

    existing ->
      existing
  end

import Ecto.Query, only: [from: 2]

# =========================================================================
# 🖼️ 2. SEED: MUNICIPAL CANDIDATE VIDEO PITCH
# =========================================================================
case Repo.all(from(v in CandidateVideo, where: v.user_id == ^user.id, limit: 1)) do
  [] ->
    %CandidateVideo{}
    |> Ecto.Changeset.cast(
      %{
        title: "Affordable Housing and Transit Grid Reconstitution Plan",
        video_url: "https://googleapis.com",
        votes_count: 342,
        office_level: "municipal",
        district_code: "austin_tx",
        sub_local_name: "city_council",
        user_id: user.id
      },
      [:title, :video_url, :votes_count, :office_level, :district_code, :sub_local_name, :user_id]
    )
    |> Repo.insert()

  _ ->
    :ok
end

# =========================================================================
# ⏱️ 3. SEED: CROWDSOURCED ELECTION LIFECYCLE DEADLINE
# =========================================================================
case Repo.all(
       from(d in ElectionDeadline,
         where:
           d.office_level == "municipal" and d.district_code == "austin_tx" and
             d.sub_local_name == "city_council",
         limit: 1
       )
     ) do
  [] ->
    %ElectionDeadline{}
    |> Ecto.Changeset.cast(
      %{
        office_level: "municipal",
        district_code: "austin_tx",
        sub_local_name: "city_council",
        application_deadline: ~D[2026-10-01],
        election_date: ~D[2026-11-03],
        state: "TX",
        logged_by_id: user.id
      },
      [
        :office_level,
        :district_code,
        :sub_local_name,
        :application_deadline,
        :election_date,
        :state,
        :logged_by_id
      ]
    )
    |> Repo.insert()

  _ ->
    :ok
end

# =========================================================================
# 🏛️ 4. SEED: DEBATE EVENT & OPERATIONAL SHIFTS ROSTER
# =========================================================================
_event =
  case Repo.all(
         from(e in DebateEvent,
           where: e.office_level == "municipal" and e.district_code == "austin_tx",
           limit: 1
         )
       ) do
    [] ->
      {:ok, ev} =
        %DebateEvent{}
        |> Ecto.Changeset.cast(
          %{
            title: "City Council District Bracket Public Forum Town Hall",
            date_time: DateTime.from_naive!(~N[2026-10-15 19:00:00], "Etc/UTC"),
            venue_address: "Austin Central Public Library Auditorium, 710 W Cesar Chavez St",
            office_level: "municipal",
            district_code: "austin_tx",
            broadcast_node_url: "https://kollective.social"
          },
          [:title, :date_time, :venue_address, :office_level, :district_code, :broadcast_node_url]
        )
        |> Repo.insert()

      Repo.insert!(%DebateShift{
        role_name: "AV Stream Broadcast Technician",
        max_volunteers: 2,
        debate_event_id: ev.id
      })

      Repo.insert!(%DebateShift{
        role_name: "Physical Venue Logistics Coordinator",
        max_volunteers: 3,
        debate_event_id: ev.id
      })

      Repo.insert!(%DebateShift{
        role_name: "Establishment Party Candidate Outreach",
        max_volunteers: 4,
        debate_event_id: ev.id
      })

      ev

    [existing | _] ->
      existing
  end

# =========================================================================
# 📝 5. SEED: SAMPLE USERS, POSTS, AND EVENTS
# =========================================================================
alias Kollective.Accounts.Accounts
alias Kollective.Posts.Posts
alias Kollective.Events.Events

IO.puts("🌱 Seeding Sample Users, Posts, and Events...")

sample_users_data = [
  %{
    email: "julian.thorne@kollective.social",
    password: "Password123!",
    username: "j_thorne",
    display_name: "Julian Thorne",
    bio: "Architect of the Red Shift. Building frontline local resilience protocols.",
    location: "California",
    state: "CA",
    country: "US"
  },
  %{
    email: "marcus.vane@kollective.social",
    password: "Password123!",
    username: "marcus_vane",
    display_name: "Marcus Vane",
    bio: "Chief Coordinator for Digital Sovereignty & Grassroots Action.",
    location: "Texas",
    state: "TX",
    country: "US"
  },
  %{
    email: "city.planning@kollective.social",
    password: "Password123!",
    username: "city_planning",
    display_name: "City Planning Circle",
    bio: "Official Hub for Sector 7 Modular Living & Solar Planning.",
    location: "Austin, TX",
    state: "TX",
    country: "US"
  },
  %{
    email: "alice@example.com",
    password: "Password123!",
    username: "alice",
    display_name: "Alice",
    bio: "Decentralized activist and organizer.",
    location: "POINT(-97.7431 30.2672)",
    street_address: "100 Congress Ave",
    city_name: "Austin",
    state: "TX",
    country: "US"
  },
  %{
    email: "bob@example.com",
    password: "Password123!",
    username: "bob",
    display_name: "Bob",
    bio: "Community builder and contributor.",
    location: "POINT(-97.7431 30.2672)",
    street_address: "100 Congress Ave",
    city_name: "Austin",
    state: "TX",
    country: "US"
  }
]

created_users =
  Enum.map(sample_users_data, fn udata ->
    case Repo.get_by(User, email: udata.email) do
      nil ->
        case Accounts.register_user(udata) do
          {:ok, u} -> u
          {:error, _} -> Repo.get_by(User, username: udata.username)
        end

      existing ->
        existing
    end
  end)

# Guarantee deterministic seed location for test users
Repo.update_all(
  from(u in User, where: u.username in ["alice", "bob"]),
  set: [
    location: "POINT(-97.7431 30.2672)",
    street_address: "100 Congress Ave",
    city_name: "Austin",
    state: "TX",
    country: "US"
  ]
)

julian = Repo.get_by(User, username: "j_thorne") || user
marcus = Repo.get_by(User, username: "marcus_vane") || user
city_hub = Repo.get_by(User, username: "city_planning") || user
alice = Repo.get_by(User, username: "alice") || user
bob = Repo.get_by(User, username: "bob") || user

metro_tenants =
  case Repo.get_by(User, username: "metro_tenants") do
    nil ->
      Repo.insert!(%User{
        display_name: "Metro Tenant Union",
        username: "metro_tenants",
        email: "contact@metrotenants.org",
        bio: "City-wide union coordinating grassroots housing action and tenant defense.",
        type: :organization,
        badge_type: "organization",
        is_verified: true,
        location: "POINT(-97.7431 30.2672)",
        city_name: "Austin",
        state: "TX",
        country: "US"
      })

    existing ->
      existing
  end

if alice && metro_tenants do
  case Repo.get_by(Kollective.Accounts.OrganizationMembership,
         user_id: alice.id,
         organization_id: metro_tenants.id
       ) do
    nil ->
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: alice.id,
        organization_id: metro_tenants.id,
        role: :admin,
        status: :approved
      })

    _existing ->
      :ok
  end
end

if bob && metro_tenants do
  case Repo.get_by(Kollective.Accounts.OrganizationMembership,
         user_id: bob.id,
         organization_id: metro_tenants.id
       ) do
    nil ->
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: bob.id,
        organization_id: metro_tenants.id,
        role: :contributor,
        status: :approved
      })

    _existing ->
      :ok
  end
end

daily_chronicle =
  case Repo.get_by(User, username: "daily_chronicle") || Repo.get_by(User, display_name: "The Daily Chronicle") do
    nil ->
      Repo.insert!(%User{
        display_name: "The Daily Chronicle",
        username: "daily_chronicle",
        email: "contact@dailychronicle.com",
        bio: "Independent municipal newsprint and investigative bulletin.",
        type: :organization,
        badge_type: "organization",
        is_verified: true,
        location: "POINT(-97.7431 30.2672)",
        street_address: "100 Congress Ave",
        city_name: "Austin",
        state: "TX",
        country: "US"
      })

    existing ->
      existing
  end

editor_user =
  case Repo.get_by(User, email: "editor@newspaper.com") do
    nil ->
      Repo.insert!(%User{
        display_name: "Editor",
        username: "editor_chronicle",
        email: "editor@newspaper.com",
        hashed_password: Pbkdf2.hash_pwd_salt("password123"),
        confirmed_at: DateTime.utc_now(:second),
        is_confirmed: true,
        type: :citizen,
        location: "POINT(-97.7431 30.2672)",
        street_address: "100 Congress Ave",
        city_name: "Austin",
        state: "TX",
        country: "US"
      })

    existing ->
      existing
  end

contributor_user =
  case Repo.get_by(User, email: "contributor@test.com") do
    nil ->
      Repo.insert!(%User{
        display_name: "Contributor",
        username: "contributor_chronicle",
        email: "contributor@test.com",
        hashed_password: Pbkdf2.hash_pwd_salt("password123"),
        confirmed_at: DateTime.utc_now(:second),
        is_confirmed: true,
        type: :citizen,
        location: "POINT(-97.7431 30.2672)",
        street_address: "100 Congress Ave",
        city_name: "Austin",
        state: "TX",
        country: "US"
      })

    existing ->
      existing
  end

if editor_user && daily_chronicle do
  case Repo.get_by(Kollective.Accounts.OrganizationMembership,
         user_id: editor_user.id,
         organization_id: daily_chronicle.id
       ) do
    nil ->
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: editor_user.id,
        organization_id: daily_chronicle.id,
        role: :admin,
        status: :approved
      })

    _existing ->
      :ok
  end
end

if contributor_user && daily_chronicle do
  case Repo.get_by(Kollective.Accounts.OrganizationMembership,
         user_id: contributor_user.id,
         organization_id: daily_chronicle.id
       ) do
    nil ->
      Repo.insert!(%Kollective.Accounts.OrganizationMembership{
        user_id: contributor_user.id,
        organization_id: daily_chronicle.id,
        role: :contributor,
        status: :approved
      })

    _existing ->
      :ok
  end
end


sample_posts = [
  %{
    user: alice,
    attrs: %{
      "content" => "Hello from seeds! Decentralized communities are the future.",
      "target_scope" => "world",
      "category" => "post",
      "status" => "published",
      "visibility" => "public"
    }
  },
  %{
    user: city_hub,
    attrs: %{
      "content" =>
        "The proposed vertical garden district for Sector 7 is now open for community feedback. This design incorporates modular living units and 100% solar capture. #CityPlanning #GreenGrid",
      "target_scope" => "local",
      "category" => "post",
      "status" => "published",
      "visibility" => "public"
    }
  },
  %{
    user: julian,
    attrs: %{
      "content" =>
        "Just finished the latest report on decentralized governance. The potential for Kollective99 to bridge the gap between policy and people is immense. Looking forward to the town hall next week! #Governance #Future",
      "target_scope" => "state",
      "category" => "post",
      "status" => "published",
      "visibility" => "public"
    }
  },
  %{
    user: marcus,
    attrs: %{
      "content" =>
        "After failed negotiations regarding the new digital sovereignty bill, the Kollective has authorized a full-scale national strike. This is not just a protest; it is a fundamental reclamation of our digital rights. #DigitalRights #Strike",
      "target_scope" => "country",
      "category" => "voice",
      "status" => "published",
      "visibility" => "public"
    }
  },
  %{
    user: julian,
    attrs: %{
      "content" =>
        "Mock seed: We are standing at the precipice of a new era. The current structures of data ownership are failing us. It is no longer enough to simply participate in the digital economy—we must own the digital soul of our existence.",
      "target_scope" => "world",
      "category" => "voice",
      "status" => "published",
      "visibility" => "public"
    }
  }
]

Enum.each(sample_posts, fn %{user: u, attrs: a} ->
  if u do
    content = a["content"]
    existing = Repo.one(from p in Kollective.Posts.Post, where: p.user_id == ^u.id and (p.content == ^content or p.text == ^content), limit: 1)
    if is_nil(existing) do
      case Posts.create_post(u, a) do
        {:ok, post} -> IO.puts("Created post #{post.id} for #{u.username}")
        {:error, cs} -> IO.puts("Failed to create post for #{u.username}: #{inspect(cs.errors)}")
      end
    else
      IO.puts("Post already exists for #{u.username}: #{existing.id}")
    end
  end
end)

sample_events = [
  %{
    user: alice,
    attrs: %{
      "title" => "Downtown Austin Tech Meetup",
      "description" =>
        "A grassroots gathering of local technologists and open-source advocates in downtown Austin.",
      "category" => "Technology",
      "participation_format" => "in_person",
      "location_name" => "Downtown Tech Hub",
      "street" => "100 Congress Ave",
      "city_name" => "Austin",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 30.2660,
      "longitude" => -97.7440,
      "start_time" => DateTime.from_naive!(~N[2026-11-15 14:00:00], "Etc/UTC"),
      "end_time" => DateTime.from_naive!(~N[2026-11-15 17:00:00], "Etc/UTC"),
      "target_scope" => "local"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "Central Texas Music Festival",
      "description" =>
        "Annual indie music gathering bringing artists together across Central Texas.",
      "category" => "Music",
      "participation_format" => "in_person",
      "location_name" => "Round Rock Amphitheater",
      "street" => "300 Round Rock Ave",
      "city_name" => "Round Rock",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 30.5083,
      "longitude" => -97.6789,
      "start_time" => DateTime.from_naive!(~N[2026-11-20 18:00:00], "Etc/UTC"),
      "end_time" => DateTime.from_naive!(~N[2026-11-20 22:00:00], "Etc/UTC"),
      "target_scope" => "state"
    }
  },
  %{
    user: marcus,
    attrs: %{
      "title" => "San Antonio Cultural Community Fair",
      "description" =>
        "A vibrant celebration of food, arts, and community heritage in the Alamo City.",
      "category" => "Community & culture",
      "participation_format" => "in_person",
      "location_name" => "Alamo Cultural Plaza",
      "street" => "100 Alamo Plaza",
      "city_name" => "San Antonio",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 29.4260,
      "longitude" => -98.4861,
      "start_time" => DateTime.from_naive!(~N[2026-11-25 10:00:00], "Etc/UTC"),
      "end_time" => DateTime.from_naive!(~N[2026-11-25 16:00:00], "Etc/UTC"),
      "target_scope" => "state"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "Silicon Valley AI Summit",
      "description" =>
        "Global summit on decentralized artificial intelligence systems and machine intelligence.",
      "category" => "Technology",
      "participation_format" => "in_person",
      "location_name" => "San Jose Convention Center",
      "street" => "150 W San Carlos St",
      "city_name" => "San Jose",
      "origin_state" => "CA",
      "origin_country" => "US",
      "latitude" => 37.3320,
      "longitude" => -121.8890,
      "start_time" => DateTime.from_naive!(~N[2026-11-15 09:00:00], "Etc/UTC"),
      "end_time" => DateTime.from_naive!(~N[2026-11-15 17:00:00], "Etc/UTC"),
      "target_scope" => "world"
    }
  },
  %{
    user: city_hub,
    attrs: %{
      "title" => "Golden State Ecology Conference",
      "description" =>
        "Exploring coastal climate resilience and ocean habitat preservation along the Pacific.",
      "category" => "Charity & causes",
      "participation_format" => "in_person",
      "location_name" => "Ocean Beach Pavilion",
      "street" => "1000 Great Hwy",
      "city_name" => "San Francisco",
      "origin_state" => "CA",
      "origin_country" => "US",
      "latitude" => 37.7749,
      "longitude" => -122.4194,
      "start_time" => DateTime.from_naive!(~N[2026-12-01 11:00:00], "Etc/UTC"),
      "end_time" => DateTime.from_naive!(~N[2026-12-01 15:00:00], "Etc/UTC"),
      "target_scope" => "state"
    }
  },
  %{
    user: marcus,
    attrs: %{
      "title" => "Emergency Housing Protest",
      "description" =>
        "Protest against sudden rent increases and corporate landlord displacement in District 4. Bring signs and peaceful determination.",
      "category" => "protest",
      "participation_format" => "in_person",
      "location_name" => "City Hall Plaza",
      "street" => "100 Congress Ave",
      "city_name" => "Austin",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 30.2672,
      "longitude" => -97.7431,
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 2, :second),
      "target_scope" => "local"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "District 4 Safety Town Hall",
      "description" =>
        "Discussion on neighborhood safety, community watch setup, and mutual aid network distribution.",
      "category" => "town_hall",
      "participation_format" => "in_person",
      "location_name" => "St. Jude Community Center",
      "street" => "400 East 5th St",
      "city_name" => "Austin",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 30.2650,
      "longitude" => -97.7390,
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 3, :second),
      "target_scope" => "local"
    }
  },
  %{
    user: alice,
    attrs: %{
      "title" => "Healthcare Workers Solidarity Rally",
      "description" =>
        "Rallying together in solidarity with regional healthcare and frontline medical workers at the Capitol.",
      "category" => "rally",
      "participation_format" => "in_person",
      "location_name" => "Texas State Capitol Grounds",
      "street" => "1100 Congress Ave",
      "city_name" => "Austin",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 30.2747,
      "longitude" => -97.7404,
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 5, :second),
      "target_scope" => "local"
    }
  },
  %{
    user: marcus,
    attrs: %{
      "title" => "Clean Energy Jobs Rally",
      "description" =>
        "Statewide mobilization demanding community clean energy workforce investments and public grid expansion.",
      "category" => "rally",
      "participation_format" => "in_person",
      "location_name" => "Alamo Plaza Public Grounds",
      "street" => "300 Alamo Plaza",
      "city_name" => "San Antonio",
      "origin_state" => "TX",
      "origin_country" => "US",
      "latitude" => 29.4260,
      "longitude" => -98.4861,
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 6, :second),
      "target_scope" => "state"
    }
  },
  %{
    user: city_hub,
    attrs: %{
      "title" => "Digital Sovereignty Virtual Summit",
      "description" =>
        "Global online conference discussing mesh networks, encrypted identity validation, and civic digital rights.",
      "category" => "meeting",
      "participation_format" => "online_virtual",
      "location_name" => "Virtual Stream Node",
      "location_url" => "https://kollective.social/stream/sovereignty",
      "city_name" => "Austin",
      "origin_state" => "TX",
      "origin_country" => "US",
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 7, :second),
      "target_scope" => "world"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "Pacific Climate Action Protest",
      "description" =>
        "Mass mobilization demanding coastal preservation, habitat protection, and halting destructive offshore drilling.",
      "category" => "protest",
      "participation_format" => "in_person",
      "location_name" => "Embarcadero Plaza",
      "street" => "1 Market St",
      "city_name" => "San Francisco",
      "origin_state" => "CA",
      "origin_country" => "US",
      "latitude" => 37.7749,
      "longitude" => -122.4194,
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 10, :second),
      "target_scope" => "world"
    }
  }
]

Enum.each(sample_events, fn %{user: u, attrs: a} ->
  if u do
    title = a["title"]
    existing = Repo.one(from e in Kollective.Events.Event, where: e.title == ^title, limit: 1)
    if is_nil(existing) do
      case Events.create_event(u, a) do
        {:ok, ev} -> IO.puts("Created event #{ev.title}")
        {:error, cs} -> IO.puts("Failed to create event #{title}: #{inspect(cs.errors)}")
      end
    else
      IO.puts("Event already exists: #{title}")
      update_set = [
        latitude: a["latitude"],
        longitude: a["longitude"],
        origin_state: a["origin_state"],
        origin_country: a["origin_country"] || "US",
        target_scope: String.to_atom(a["target_scope"] || "local"),
        category: a["category"],
        participation_format: a["participation_format"],
        location_name: a["location_name"],
        street: a["street"],
        location_url: a["location_url"],
        start_time: a["start_time"],
        end_time: a["end_time"]
      ]
      update_set =
        if a["longitude"] && a["latitude"] do
          Keyword.put(update_set, :location, %Geo.Point{coordinates: {a["longitude"], a["latitude"]}, srid: 4326})
        else
          update_set
        end

      from(e in Kollective.Events.Event, where: e.title == ^title)
      |> Repo.update_all(set: update_set)
    end
  end
end)

# Ensure deterministic coordinates and origin states for sample events
Repo.update_all(
  from(e in Kollective.Events.Event, where: e.title in ["Downtown Austin Tech Meetup", "Central Texas Music Festival", "San Antonio Cultural Community Fair"]),
  set: [origin_state: "TX"]
)
Repo.update_all(
  from(e in Kollective.Events.Event, where: e.title in ["Silicon Valley AI Summit", "Golden State Ecology Conference"]),
  set: [origin_state: "CA"]
)

IO.puts("✅ Sample Users, Posts, and Events successfully seeded!")

# =========================================================================
# 🏢 5.5 SEED: LOCAL BUSINESSES & COMMUNITY PROPOSALS
# =========================================================================
alias Kollective.Businesses.Business

sample_businesses_data = [
  %{
    name: "Austin Coffee Co-op",
    description: "A community-supported worker cooperative serving ethical organic espresso and fair-trade coffee.",
    type: "existing",
    category: "food_beverage",
    sub_category: "cafe_coffee",
    address: "200 Congress Ave",
    city: "Austin",
    state: "TX",
    zip: "78701",
    country: "US",
    phone: "512-555-0101",
    email: "contact@austincoffee.coop",
    website: "https://austincoffee.coop",
    legal_structure: "Worker-Owned Co-op",
    year_established: 2021,
    number_of_employees: 8,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.7420, 30.2680}, srid: 4326},
    metadata: %{
      "business_hours" => "07:00 AM - 05:00 PM",
      "hours" => "07:00 AM - 05:00 PM",
      "services" => ["Espresso Bar", "Bakery Goods", "Community Meeting Space"],
      "tags" => ["Worker-Owned", "Organic", "Fair Wage Certified"],
      "rating" => 4.9,
      "reviews_count" => 42
    }
  },
  %{
    name: "South Austin Maker Space",
    description: "Shared community workshop featuring woodworking equipment, 3D printers, and digital fabrication tools.",
    type: "existing",
    category: "manufacturing",
    sub_category: "artisan_crafting",
    address: "1500 South Congress Ave",
    city: "Austin",
    state: "TX",
    zip: "78704",
    country: "US",
    phone: "512-555-0102",
    email: "info@southaustinmakers.org",
    website: "https://southaustinmakers.org",
    legal_structure: "Cooperative",
    year_established: 2020,
    number_of_employees: 6,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.7510, 30.2450}, srid: 4326},
    metadata: %{
      "business_hours" => "09:00 AM - 09:00 PM",
      "hours" => "09:00 AM - 09:00 PM",
      "services" => ["Woodworking Tools", "Laser Cutting", "Tool Library"],
      "tags" => ["Cooperative", "Tool Library", "Eco-Friendly"],
      "rating" => 5.0,
      "reviews_count" => 28
    }
  },
  %{
    name: "North Austin Tech Lab",
    description: "Open source software development and decentralized networking laboratory for civic tech infrastructure.",
    type: "existing",
    category: "technology",
    sub_category: "software_saas",
    address: "8900 Burnet Rd",
    city: "Austin",
    state: "TX",
    zip: "78757",
    country: "US",
    phone: "512-555-0103",
    email: "hello@northaustintech.io",
    website: "https://northaustintech.io",
    legal_structure: "LLC",
    year_established: 2022,
    number_of_employees: 12,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.7280, 30.3650}, srid: 4326},
    metadata: %{
      "business_hours" => "08:30 AM - 06:00 PM",
      "hours" => "08:30 AM - 06:00 PM",
      "services" => ["Mesh Networking", "Security Auditing", "Civic Software"],
      "tags" => ["Open Source", "Civic Tech", "Decentralized"],
      "rating" => 4.8,
      "reviews_count" => 19
    }
  },
  %{
    name: "Round Rock Artisans",
    description: "Local artisan collective retail market offering handcrafted ceramics, textiles, and neighborhood goods.",
    type: "existing",
    category: "retail",
    sub_category: "handmade_crafts",
    address: "100 East Main St",
    city: "Round Rock",
    state: "TX",
    zip: "78664",
    country: "US",
    phone: "512-555-0104",
    email: "team@roundrockartisans.coop",
    website: "https://roundrockartisans.coop",
    legal_structure: "Cooperative",
    year_established: 2019,
    number_of_employees: 5,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.6789, 30.5083}, srid: 4326},
    metadata: %{
      "business_hours" => "10:00 AM - 07:00 PM",
      "hours" => "10:00 AM - 07:00 PM",
      "services" => ["Handmade Pottery", "Textile Weaving", "Local Retail"],
      "tags" => ["Local Sourcing", "Artisan", "Cooperative"],
      "rating" => 4.7,
      "reviews_count" => 33
    }
  },
  %{
    name: "San Marcos Green Energy",
    description: "Community-owned solar power microgrid generating clean renewable power for local households.",
    type: "existing",
    category: "sustainable_energy",
    sub_category: "solar_coop",
    address: "300 North Guadalupe St",
    city: "San Marcos",
    state: "TX",
    zip: "78666",
    country: "US",
    phone: "512-555-0105",
    email: "energy@sanmarcosgreen.org",
    website: "https://sanmarcosgreen.org",
    legal_structure: "Community Land Trust",
    year_established: 2023,
    number_of_employees: 15,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.9414, 29.8833}, srid: 4326},
    metadata: %{
      "business_hours" => "08:00 AM - 05:00 PM",
      "hours" => "08:00 AM - 05:00 PM",
      "services" => ["Rooftop Solar", "Battery Backup", "Energy Auditing"],
      "tags" => ["Eco-Friendly", "Community Funded", "Renewable"],
      "rating" => 5.0,
      "reviews_count" => 15
    }
  },
  %{
    name: "San Antonio Community Press",
    description: "Independent radical bookstore, community print shop, and literary space supporting local authors.",
    type: "existing",
    category: "retail",
    sub_category: "bookstore",
    address: "115 Broadway St",
    city: "San Antonio",
    state: "TX",
    zip: "78205",
    country: "US",
    phone: "210-555-0106",
    email: "press@sanantoniopress.coop",
    website: "https://sanantoniopress.coop",
    legal_structure: "Worker-Owned Co-op",
    year_established: 2018,
    number_of_employees: 7,
    verification_status: "verified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-98.4936, 29.4241}, srid: 4326},
    metadata: %{
      "business_hours" => "11:00 AM - 08:00 PM",
      "hours" => "11:00 AM - 08:00 PM",
      "services" => ["Bookstore", "Print Services", "Zine Publishing"],
      "tags" => ["Worker-Owned", "Literary", "Community"],
      "rating" => 4.9,
      "reviews_count" => 57
    }
  }
]

Enum.each(sample_businesses_data, fn bdata ->
  name = bdata.name
  case Repo.get_by(Business, name: name) do
    nil ->
      %Business{}
      |> Ecto.Changeset.change(bdata)
      |> Repo.insert!()
      IO.puts("   ✅ Seeded business: #{name}")

    existing ->
      existing
      |> Ecto.Changeset.change(bdata)
      |> Repo.update!()
      IO.puts("   🔄 Updated business: #{name}")
  end
end)

sample_proposals_data = [
  %{
    name: "Austin Community Bio-Pharmacy",
    description: "Grassroots community pharmacy dispensing affordable generic medications and botanical health supplies.",
    type: "proposals",
    category: "healthcare",
    sub_category: "medical_clinic",
    address: "500 East 7th St",
    city: "Austin",
    state: "TX",
    zip: "78701",
    country: "US",
    verification_status: "unverified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.7431, 30.2672}, srid: 4326},
    metadata: %{
      "funding_data" => %{
        "funding_required" => true,
        "fundingGoal" => 60000,
        "money_required" => 60000,
        "minInvest" => 50,
        "minimum_amount" => 50,
        "maxInvest" => 5000,
        "maximum_amount" => 5000,
        "percent" => 35,
        "daysLeft" => 42,
        "status" => "Active",
        "participants" => "24 Members"
      },
      "location" => "Austin, TX",
      "owner_handle" => "alice"
    }
  },
  %{
    name: "Texas Solar Microgrid Initiative",
    description: "Resilient neighborhood rooftop solar installations and neighborhood battery storage cooperative.",
    type: "proposals",
    category: "sustainable_energy",
    sub_category: "solar_coop",
    address: "1200 Lavaca St",
    city: "Austin",
    state: "TX",
    zip: "78701",
    country: "US",
    verification_status: "unverified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.7430, 30.2750}, srid: 4326},
    metadata: %{
      "funding_data" => %{
        "funding_required" => true,
        "fundingGoal" => 120000,
        "money_required" => 120000,
        "minInvest" => 100,
        "minimum_amount" => 100,
        "maxInvest" => 10000,
        "maximum_amount" => 10000,
        "percent" => 60,
        "daysLeft" => 28,
        "status" => "Active",
        "participants" => "58 Members"
      },
      "location" => "Austin, TX",
      "owner_handle" => "alice"
    }
  },
  %{
    name: "Central Texas Grain Milling Co-op",
    description: "Regional organic flour and heritage heirloom grain processing facility supporting sustainable farming.",
    type: "proposals",
    category: "agriculture",
    sub_category: "organic_farm",
    address: "450 West Palm Valley Blvd",
    city: "Round Rock",
    state: "TX",
    zip: "78664",
    country: "US",
    verification_status: "unverified",
    user_id: alice.id,
    location: %Geo.Point{coordinates: {-97.6800, 30.5100}, srid: 4326},
    metadata: %{
      "funding_data" => %{
        "funding_required" => true,
        "fundingGoal" => 85000,
        "money_required" => 85000,
        "minInvest" => 25,
        "minimum_amount" => 25,
        "maxInvest" => 2500,
        "maximum_amount" => 2500,
        "percent" => 15,
        "daysLeft" => 55,
        "status" => "Active",
        "participants" => "12 Members"
      },
      "location" => "Round Rock, TX",
      "owner_handle" => "alice"
    }
  }
]

Enum.each(sample_proposals_data, fn pdata ->
  name = pdata.name
  case Repo.get_by(Business, name: name) do
    nil ->
      %Business{}
      |> Ecto.Changeset.change(pdata)
      |> Repo.insert!()
      IO.puts("   ✅ Seeded proposal: #{name}")

    existing ->
      existing
      |> Ecto.Changeset.change(pdata)
      |> Repo.update!()
      IO.puts("   🔄 Updated proposal: #{name}")
  end
end)

alias Kollective.Governance.Importer

# =========================================================================
# 🌐 6. SEED: DYNAMIC GLOBAL GOVERNANCE OFFICE REGISTRIES
# =========================================================================
data_dir = Application.app_dir(:kollective, "priv/repo/data/country_offices")
json_files = Path.wildcard("#{data_dir}/*.json")

IO.puts("🌱 Starting batch dynamic global office ingestion engine...")

Enum.each(json_files, fn file_path ->
  country_code = file_path |> Path.basename(".json") |> String.upcase()
  IO.puts("   ➡️  Parsing and mapping registry profiles for: [#{country_code}]")

  try do
    case Importer.import_country_json(file_path) do
      {:ok, :success} -> IO.puts("   ✅ Successfully synced [#{country_code}]")
      {:error, reason} -> IO.puts("   ⚠️ Skipped [#{country_code}]: #{inspect(reason)}")
    end
  rescue
    e -> IO.puts("   ⚠️ Skipping [#{country_code}] due to changeset validation: #{inspect(e)}")
  end
end)

IO.puts("🎉 All universal governance schema structures successfully loaded!")

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

julian = Enum.find(created_users, &(&1 && &1.username == "j_thorne")) || user
marcus = Enum.find(created_users, &(&1 && &1.username == "marcus_vane")) || user
city_hub = Enum.find(created_users, &(&1 && &1.username == "city_planning")) || user

sample_posts = [
  %{
    user: city_hub,
    attrs: %{
      "title" => "City Planning Garden District",
      "content" =>
        "The proposed vertical garden district for Sector 7 is now open for community feedback. This design incorporates modular living units and 100% solar capture. #CityPlanning #GreenGrid",
      "target_scope" => "local",
      "category" => "standard",
      "status" => "published"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "Decentralized Governance Report",
      "content" =>
        "Just finished the latest report on decentralized governance. The potential for Kollective99 to bridge the gap between policy and people is immense. Looking forward to the town hall next week! #Governance #Future",
      "target_scope" => "state",
      "category" => "popular",
      "status" => "published"
    }
  },
  %{
    user: marcus,
    attrs: %{
      "title" => "URGENT: National Strike Action confirmed for December 15th.",
      "content" =>
        "After failed negotiations regarding the new digital sovereignty bill, the Kollective has authorized a full-scale national strike. This is not just a protest; it is a fundamental reclamation of our digital rights. #DigitalRights #Strike",
      "target_scope" => "country",
      "category" => "voice",
      "status" => "published"
    }
  },
  %{
    user: julian,
    attrs: %{
      "title" => "The Digital Renaissance: Why Decentralized Identity is our Final Frontier.",
      "content" =>
        "Mock seed: We are standing at the precipice of a new era. The current structures of data ownership are failing us. It is no longer enough to simply participate in the digital economy—we must own the digital soul of our existence.",
      "target_scope" => "world",
      "category" => "voice",
      "status" => "published"
    }
  }
]

Enum.each(sample_posts, fn %{user: u, attrs: a} ->
  if u do
    Posts.create_post(u, a)
  end
end)

sample_events = [
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
      "start_time" => DateTime.utc_now() |> DateTime.add(86400 * 4, :second),
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
  }
]

Enum.each(sample_events, fn %{user: u, attrs: a} ->
  if u do
    Events.create_event(u, a)
  end
end)

IO.puts("✅ Sample Users, Posts, and Events successfully seeded!")

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

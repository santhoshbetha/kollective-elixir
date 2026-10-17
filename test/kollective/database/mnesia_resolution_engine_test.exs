defmodule Kollective.Database.MnesiaResolutionEngineTest do
  use Kollective.DataCase, async: false
  require Logger

  alias Kollective.Database.MnesiaResolutionEngine
  alias Kollective.Moderation.Incident
  alias Kollective.Repo

  setup do
    # Clear out local Mnesia structures before running the concurrent run
    :mnesia.clear_table(:scholar_incidents)

    # Seed a baseline test reporter inside your relational Postgres schema
    {:ok, user} =
      Repo.insert(%Kollective.Accounts.User{
        email: "test_mod@kollective.org",
        username: "test_mod_user"
      })

    # Create an initial pending incident inside Postgres
    incident_attrs = %{
      status: "pending",
      country_code: "US",
      origin_node_atom: "node_test@127.0.0.1",
      description: "Testing highly concurrent cluster lock acquisition profiles.",
      reporter_id: user.id
    }

    {:ok, incident} = %Incident{} |> Incident.changeset(incident_attrs) |> Repo.insert()

    # Hydrate Mnesia manually to simulate baseline state matching your production Hydrator loop
    :mnesia.transaction(fn ->
      :mnesia.write({
        :scholar_incidents,
        to_string(incident.id),
        incident.status,
        incident.country_code,
        incident.origin_node_atom,
        "test_target",
        System.system_time(:second),
        nil,
        nil
      })
    end)

    {:ok, incident: incident}
  end

  test "concurrency storm: ensures cluster prevents double-booking under heavy load", %{
    incident: incident
  } do
    incident_id = to_string(incident.id)

    # 1️⃣ SIMULATE 50 CONCURRENT OPERATORS CLICKING "CLAIM" AT THE EXACT SAME MILLISECOND
    num_concurrent_operators = 50

    # Map out separate tasks, each passing a unique operator id
    tasks =
      Enum.map(1..num_concurrent_operators, fn _idx ->
        Task.async(fn ->
          # Introduce a tiny microsecond randomized jitter to simulate organic high load
          operator_id = Ecto.ULID.generate()
          MnesiaResolutionEngine.claim_incident(incident_id, operator_id)
        end)
      end)

    # 2️⃣ COLLECT TRANSACTION RESULTS ACROSS THE BEAM PROCESS TREE
    results = Enum.map(tasks, &Task.await/1)

    # 3️⃣ ASSERT STRICT LOCK CONTRACT RULES
    claims_succeeded = Enum.filter(results, fn res -> res == {:ok, :claimed} end)
    claims_locked = Enum.filter(results, fn res -> res == {:error, :incident_already_locked} end)

    # Core distributed invariants validation:
    assert length(claims_succeeded) == 1,
           "❌ CRITICAL: More than one operator successfully claimed the exclusive lock!"

    assert length(claims_locked) == num_concurrent_operators - 1

    # 4️⃣ VERIFY COHESION ACROSS THE COLD STORAGE LAYER (POSTGRES)
    updated_pg_record = Repo.get!(Incident, incident.id)
    assert updated_pg_record.status == "pending"
    refute is_nil(updated_pg_record.leased_by_id)
    refute is_nil(updated_pg_record.leased_until)

    # 5️⃣ VERIFY COHESION ACROSS MEMORY TABLES (MNESIA)
    {:atomic, [mnesia_record]} =
      :mnesia.transaction(fn -> :mnesia.read(:scholar_incidents, incident_id) end)

    element_list = Tuple.to_list(mnesia_record)

    # Verify Mnesia parameters match the Postgres transaction logs perfectly
    assert Enum.at(element_list, 7) == to_string(updated_pg_record.leased_by_id)
  end
end

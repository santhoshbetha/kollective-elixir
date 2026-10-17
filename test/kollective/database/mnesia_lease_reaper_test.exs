defmodule Kollective.Database.MnesiaLeaseReaperTest do
  use Kollective.DataCase, async: false

  alias Kollective.Database.MnesiaLeaseReaper
  alias Kollective.Moderation.Incident
  alias Kollective.Repo

  setup do
    if :scholar_incidents in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:scholar_incidents)
    end

    {:ok, moderator} =
      Repo.insert(%Kollective.Accounts.User{
        email: "reaper_mod@kollective.org",
        username: "reaper_mod"
      })

    {:ok, moderator: moderator}
  end

  test "reaps expired leases in Mnesia and Postgres", %{moderator: moderator} do
    now = System.system_time(:second)
    expired_time = now - 100
    incident_id = Ecto.ULID.generate()

    # Create expired incident in Postgres
    {:ok, incident} =
      %Incident{}
      |> Incident.changeset(%{
        id: incident_id,
        status: "pending",
        country_code: "US",
        origin_node_atom: "node_test@127.0.0.1",
        description: "Reaper test incident",
        reporter_id: moderator.id,
        leased_by_id: moderator.id,
        leased_until: DateTime.from_unix!(expired_time)
      })
      |> Repo.insert()

    # Write expired record into Mnesia
    :mnesia.transaction(fn ->
      :mnesia.write({
        :scholar_incidents,
        to_string(incident.id),
        "pending",
        "US",
        "target_user",
        "Reaper test incident",
        now - 200,
        to_string(moderator.id),
        expired_time
      })
    end)

    # Trigger reap on the already running supervisor reaper
    reaper = Process.whereis(MnesiaLeaseReaper)
    send(reaper, :execute_reap)

    # Allow GenServer to process
    :timer.sleep(150)

    # Verify Mnesia record had lease cleared
    {:atomic, [mnesia_record]} =
      :mnesia.transaction(fn -> :mnesia.read(:scholar_incidents, to_string(incident.id)) end)

    element = Tuple.to_list(mnesia_record)
    assert Enum.at(element, 7) == nil
    assert Enum.at(element, 8) == nil

    # Verify Postgres record had lease cleared
    pg_record = Repo.get!(Incident, incident.id)
    assert is_nil(pg_record.leased_by_id)
    assert is_nil(pg_record.leased_until)
  end

  test "reaps Mnesia record even if not present in Postgres" do
    now = System.system_time(:second)
    expired_time = now - 100
    fake_id = "orphan_mnesia_incident_123"

    # Write orphaned expired record into Mnesia only
    :mnesia.transaction(fn ->
      :mnesia.write({
        :scholar_incidents,
        fake_id,
        "pending",
        "US",
        "orphan_user",
        "Orphaned Mnesia record",
        now - 200,
        "some_operator",
        expired_time
      })
    end)

    reaper = Process.whereis(MnesiaLeaseReaper)
    send(reaper, :execute_reap)

    :timer.sleep(150)

    {:atomic, [mnesia_record]} =
      :mnesia.transaction(fn -> :mnesia.read(:scholar_incidents, fake_id) end)

    element = Tuple.to_list(mnesia_record)
    assert Enum.at(element, 7) == nil
    assert Enum.at(element, 8) == nil
  end
end

defmodule Kollective.Database.MnesiaQueueEngineTest do
  use Kollective.DataCase, async: false

  alias Kollective.Database.MnesiaQueueEngine
  alias Kollective.Repo

  setup do
    # Ensure :scholar_incidents exists and is empty
    if :scholar_incidents in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:scholar_incidents)
    end

    {:ok, moderator} =
      Repo.insert(%Kollective.Accounts.User{
        email: "moderator_test@kollective.org",
        username: "mod_test",
        is_moderator: true,
        country: "US"
      })

    {:ok, moderator: moderator}
  end

  describe "lease_next_incident/3" do
    test "successfully leases an available incident ticket", %{moderator: moderator} do
      now = System.system_time(:second)
      incident_id = Ecto.ULID.generate()

      # Write a test incident directly to Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          incident_id,
          "pending",
          "US",
          "offending_user",
          "Flagged for offensive content",
          now - 60,
          nil,
          nil
        })
      end)

      assert {:ok, ticket} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", false)
      assert ticket.id == incident_id
      assert ticket.status == "pending"
      assert ticket.target_username == "offending_user"
      assert ticket.country_code == "US"
      assert is_binary(ticket.inserted_at)

      # Verify the record in Mnesia is now leased
      {:atomic, [record]} = :mnesia.transaction(fn -> :mnesia.read(:scholar_incidents, incident_id) end)
      list = Tuple.to_list(record)
      assert Enum.at(list, 7) == to_string(moderator.id)
      assert is_integer(Enum.at(list, 8))
      assert Enum.at(list, 8) > now
    end

    test "respects FIFO ordering (leases oldest incident first)", %{moderator: moderator} do
      now = System.system_time(:second)
      older_id = Ecto.ULID.generate()
      newer_id = Ecto.ULID.generate()

      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          newer_id,
          "pending",
          "US",
          "newer_user",
          "Newer infraction",
          now - 10,
          nil,
          nil
        })

        :mnesia.write({
          :scholar_incidents,
          older_id,
          "pending",
          "US",
          "older_user",
          "Older infraction",
          now - 300,
          nil,
          nil
        })
      end)

      # Should lease the older incident first
      assert {:ok, ticket1} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", false)
      assert ticket1.id == older_id

      # Next lease should get the newer incident
      assert {:ok, ticket2} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", false)
      assert ticket2.id == newer_id
    end

    test "respects geofencing routing", %{moderator: moderator} do
      now = System.system_time(:second)
      in_id = Ecto.ULID.generate()

      # Ticket from India (IN)
      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          in_id,
          "pending",
          "IN",
          "in_user",
          "Infraction in India",
          now - 10,
          nil,
          nil
        })
      end)

      # US moderator without global clearance cannot lease Indian ticket
      assert {:error, :empty_queue} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", false)

      # Global moderator CAN lease Indian ticket
      assert {:ok, ticket} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", true)
      assert ticket.id == in_id
    end

    test "returns {:error, :empty_queue} when no pending tickets exist", %{moderator: moderator} do
      assert {:error, :empty_queue} = MnesiaQueueEngine.lease_next_incident(moderator.id, "US", false)
    end

    test "prevents double leasing under concurrent requests", %{moderator: moderator} do
      now = System.system_time(:second)
      incident_id = Ecto.ULID.generate()

      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          incident_id,
          "pending",
          "US",
          "target_user",
          "Single available incident",
          now - 50,
          nil,
          nil
        })
      end)

      # Run 20 concurrent lease attempts
      tasks =
        Enum.map(1..20, fn _ ->
          Task.async(fn ->
            MnesiaQueueEngine.lease_next_incident(moderator.id, "US", true)
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      succeeded = Enum.filter(results, fn res -> match?({:ok, _}, res) end)
      empty_queues = Enum.filter(results, fn res -> res == {:error, :empty_queue} end)

      assert length(succeeded) == 1
      assert length(empty_queues) == 19
    end
  end
end

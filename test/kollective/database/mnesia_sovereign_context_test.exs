defmodule Kollective.Database.MnesiaSovereignContextTest do
  use ExUnit.Case, async: false

  alias Kollective.Database.MnesiaSovereignContext

  setup do
    if :node_sovereign_operators in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:node_sovereign_operators)
    end

    :ok
  end

  test "grants, lists, and revokes local operator clearance" do
    # 1. Grant clearance
    assert {:ok, %{username: "alice", role: "moderator"}} =
             MnesiaSovereignContext.grant_node_clearance("@Alice", "moderator", "admin_root")

    assert {:ok, %{username: "bob", role: "admin"}} =
             MnesiaSovereignContext.grant_node_clearance("bob", "admin", "admin_root")

    # 2. List operators
    operators = MnesiaSovereignContext.list_local_operators()
    usernames = Enum.map(operators, & &1.username) |> Enum.sort()
    assert usernames == ["alice", "bob"]

    alice = Enum.find(operators, &(&1.username == "alice"))
    assert alice.role == "moderator"
    assert alice.granted_by == "admin_root"
    assert is_binary(alice.inserted_at)

    # 3. Revoke clearance
    assert :ok = MnesiaSovereignContext.revoke_node_clearance("alice")

    remaining = MnesiaSovereignContext.list_local_operators()
    assert Enum.map(remaining, & &1.username) == ["bob"]
  end
end

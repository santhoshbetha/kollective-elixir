defmodule Kollective.Database.MnesiaSovereignContext do
  @compile {:no_warn_undefined, :mnesia}

  @doc """
  Lists all local administrative and moderator accounts whitelisted on this specific node instance.
  """
  def list_local_operators() do
    case :mnesia.transaction(fn -> :mnesia.all_keys(:node_sovereign_operators) end) do
      {:atomic, keys} ->
        Enum.flat_map(keys, fn key ->
          case :mnesia.dirty_read(:node_sovereign_operators, key) do
            [record] ->
              list = Tuple.to_list(record)

              [
                %{
                  username: Enum.at(list, 1),
                  role: Enum.at(list, 2),
                  granted_by: Enum.at(list, 3),
                  inserted_at: Enum.at(list, 4)
                }
              ]

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  @doc """
  Grants server keys to a local citizen directly on this hardware node.
  """
  def grant_node_clearance(username, role, granted_by_username) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    # Strip "@" prefix strings and normalize downcase
    clean_username = String.trim(username) |> String.replace_prefix("@", "") |> String.downcase()

    record = {:node_sovereign_operators, clean_username, role, granted_by_username, now}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> {:ok, %{username: clean_username, role: role}}
      _ -> {:error, :write_failed}
    end
  end

  @doc """
  Revokes server permissions instantly from a local node operator.
  """
  def revoke_node_clearance(username) do
    case :mnesia.transaction(fn -> :mnesia.delete({:node_sovereign_operators, username}) end) do
      {:atomic, :ok} -> :ok
      _ -> {:error, :delete_failed}
    end
  end
end

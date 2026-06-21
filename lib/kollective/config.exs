# lib/kollective/config.exs
defmodule Kollective.Config do
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Config.Config

  @doc """
  Attempts to read a dynamic setting from the database table pool.
  Falls back immediately to native mix config/runtime values if missing.
  """
  def get(group, key, default \\ nil) do
    group_str = Atom.to_string(group)
    key_str = Atom.to_string(key)

    case Repo.get_by(Config, group: group_str, key: key_str) do
      nil ->
        # Fallback to local system application compile-time environment variables
        Application.get_env(:kollective, group, [])
        |> Keyword.get(key, default)

      record ->
        # Safely extract and re-inflate stored binary data structures back into Elixir values
        :erlang.binary_to_term(record.value)
    end
  end

  @doc "Saves or updates a live runtime setting inside the database."
  def put(group, key, value) do
    group_str = Atom.to_string(group)
    key_str = Atom.to_string(key)
    binary_value = :erlang.term_to_binary(value)

    %Config{}
    |> Config.changeset(%{group: group_str, key: key_str, value: binary_value})
    |> Repo.insert(
      on_conflict: [set: [value: binary_value]],
      conflict_target: [:group, :key]
    )
  end
end

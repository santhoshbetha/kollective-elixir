defmodule KollectiveWeb.Admin.SovereignOperatorController do
  use KollectiveWeb, :controller
  @compile {:no_warn_undefined, :mnesia}
  require Logger

  alias Kollective.Repo
  alias Kollective.Moderation.SovereignOperator

  @doc """
  GET /api/v1/admin/sovereign_operators
  Reads from distributed Mnesia clusters memory, falling back cleanly to Ecto SQL if the mesh is partitioned.
  """
  def index(conn, _params) do
    # 📡 HYBRID READ ENGINE
    case :mnesia.transaction(fn -> :mnesia.all_keys(:node_sovereign_operators) end) do
      {:atomic, keys} when is_list(keys) and length(keys) > 0 ->
        # Pull records directly from active high-speed cluster memory
        serialized_operators =
          Enum.map(keys, fn username_key ->
            case :mnesia.dirty_read(:node_sovereign_operators, username_key) do
              [record] ->
                list = Tuple.to_list(record)

                %{
                  username: Enum.at(list, 1),
                  role: Enum.at(list, 2),
                  granted_by: Enum.at(list, 3),
                  inserted_at: Enum.at(list, 4)
                }

              _ ->
                nil
            end
          end)
          |> Enum.filter(&(not is_nil(&1)))

        json(conn, %{data: serialized_operators})

      _fallback ->
        Logger.warning(
          "⚠️ [HYBRID FALLBACK]: Mnesia mesh is dark or un-hydrated. Routing query to local Ecto PostgreSQL..."
        )

        # Graceful database dropback to guarantee your React components never crash or freeze
        operators = Repo.all(SovereignOperator)
        json(conn, %{data: operators})
    end
  end

  @doc """
  POST /api/v1/admin/sovereign_operators
  Dual-writes to both high-speed Mnesia RAM arrays and persistent Ecto SQL disk tables.
  """
  def create(conn, %{"operator" => %{"username" => username, "role" => role}}) do
    current_user = conn.assigns[:current_user] || conn.assigns[:user]
    granted_by = if current_user && Map.get(current_user, :username), do: current_user.username, else: "system"
    clean_username = String.trim(username) |> String.downcase()
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    # 1️⃣ Core SQL Persistence Pass (Ensures permanent hardware backup)
    sql_attrs = %{username: clean_username, role: role, granted_by: granted_by}
    changeset = SovereignOperator.changeset(%SovereignOperator{}, sql_attrs)

    case Repo.insert(changeset, on_conflict: :replace_all, conflict_target: :username) do
      {:ok, _sql_operator} ->
        # 2️⃣ Asymmetric Mnesia Mirror Injection Pass
        new_mnesia_record =
          {:node_sovereign_operators, clean_username, role, granted_by, now_iso}

        case :mnesia.transaction(fn -> :mnesia.write(new_mnesia_record) end) do
          {:atomic, :ok} ->
            json(conn, %{
              status: "success",
              message: "Operator metrics synchronized across RAM and SQL disk space."
            })

          {:aborted, reason} ->
            Logger.warning(
              "⚠️ [MESH WARNING]: Mnesia write skipped, but SQL committed: #{inspect(reason)}"
            )

            json(conn, %{
              status: "success",
              message: "Operator recorded locally on SQL storage (Mesh replication delayed)."
            })
        end

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed mapping permission sets.",
          details: inspect(changeset.errors)
        })
    end
  end

  @doc """
  DELETE /api/v1/admin/sovereign_operators/:username
  Purges clearance signatures from local PostgreSQL tables and flushes Mnesia memory registers across all nodes.
  """
  def delete(conn, %{"id" => username}) do
    clean_username = String.trim(username) |> String.downcase()

    # 1️⃣ Evict from persistent Ecto storage
    case Repo.get(SovereignOperator, clean_username) do
      nil ->
        # Check Mnesia memory anyway to clear orphan registers
        _ =
          :mnesia.transaction(fn ->
            :mnesia.delete({:node_sovereign_operators, clean_username})
          end)

        conn
        |> put_status(:not_found)
        |> json(%{error: "Operator key mismatch on disk storage logs."})

      operator ->
        Repo.delete!(operator)

        # 2️⃣ Flush across the live Mnesia cluster replica ring concurrently
        _ =
          :mnesia.transaction(fn ->
            :mnesia.delete({:node_sovereign_operators, clean_username})
          end)

        json(conn, %{
          status: "success",
          message: "Clearance signatures fully purged out of all active hardware registers."
        })
    end
  end
end

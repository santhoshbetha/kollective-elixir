# lib/kollective_web/controllers/api/v1/debate_controller.ex
defmodule KollectiveWeb.DebateController do
  use KollectiveWeb, :controller

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Campaigns.{DebateEvent, DebateShift}

  action_fallback KollectiveWeb.FallbackController

  @doc """
  Streams debate calendars and nested volunteer arrays filtered by district bounds.
  GET /api/v1/campaigns/debates?level=congress&code=TX-10
  """
  def index_debates(conn, %{"level" => level, "code" => code}) do
    debates =
      DebateEvent
      |> where([e], e.office_level == ^level and e.district_code == ^code)
      |> order_by([e], asc: e.date_time)
      # Deeply preload worker shift assignments
      |> preload(shifts: [:volunteers])
      |> Repo.all()

    json(conn, debates)
  end

  @doc """
  Atomically binds an authenticated user ID to a logistics shift assignment slot.
  POST /api/v1/campaigns/debates/shifts/:id/claim
  """
  def claim_shift(conn, %{"id" => shift_id}) do
    user_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)

    # Fetch the exact shift inside a database lock boundary to safeguard seat limits
    Repo.transaction(fn ->
      shift =
        DebateShift
        |> where([s], s.id == ^shift_id)
        |> preload([:volunteers])
        # Enforce row-level lock against concurrent claims
        |> lock("FOR UPDATE")
        |> Repo.one!()

      current_count = Enum.count(shift.volunteers)

      cond do
        Enum.any?(shift.volunteers, &(&1.id == user_id)) ->
          Repo.rollback(:already_volunteered)

        current_count >= shift.max_volunteers ->
          Repo.rollback(:shift_capacity_filled)

        true ->
          # Atomic write insertion straight down into the many-to-many join schema matrix
          # Inject mapping via raw insert_all or Ecto changesets
          {:ok, shift_id_bin} = Ecto.ULID.dump(shift.id)
          {:ok, user_id_bin} = Ecto.ULID.dump(user_id)

          conn_insert =
            Repo.insert_all("debate_shifts_volunteers", [
              [debate_shift_id: shift_id_bin, user_id: user_id_bin]
            ])

          case conn_insert do
            {1, nil} ->
              # Return reloaded data maps to feed back into client TanStack structures
              DebateShift |> Repo.get!(shift_id) |> Repo.preload([:volunteers])

            _ ->
              Repo.rollback(:db_write_error)
          end
      end
    end)
    |> case do
      {:ok, updated_shift} ->
        conn
        |> put_status(:ok)
        |> json(updated_shift)

      {:error, :already_volunteered} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "You are already catalogued for this operational shift."})

      {:error, :shift_capacity_filled} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "This specific shift slot has reached maximum volunteer capacity."})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{error: "Transaction processing fault."})
    end
  end
end

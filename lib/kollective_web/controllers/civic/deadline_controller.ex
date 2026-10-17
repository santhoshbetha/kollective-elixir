# lib/kollective_web/controllers/api/v1/deadline_controller.ex
defmodule KollectiveWeb.DeadlineController do
  use KollectiveWeb, :controller

  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Campaigns.ElectionDeadline
  alias Kollective.Accounts.User

  action_fallback KollectiveWeb.FallbackController

  @doc """
  Streams a flat list of crowdsourced election timelines filtered by state and scope coordinates.
  GET /api/v1/campaigns/deadlines?state=TX&level=municipal&code=austin_tx
  """
  def index_deadlines(conn, %{"state" => state, "level" => office_level, "code" => district_code}) do
    base_query =
      ElectionDeadline
      |> where([d], d.state == ^state and d.office_level == ^office_level)

    # Allow a fallback match condition to track all entries across a given state tier
    query =
      if district_code == "all" do
        base_query
      else
        where(base_query, [d], d.district_code == ^district_code)
      end

    deadlines =
      query
      |> order_by([d], asc: d.application_deadline)
      |> Repo.all()

    json(conn, deadlines)
  end

  @doc """
  Commits verified ballot-access timestamps securely down into the public ledger.
  POST /api/v1/campaigns/deadlines
  """
  def create_deadline(conn, %{"deadline" => deadline_params}) do
    user_id = conn.assigns[:current_user_id] || (conn.assigns[:current_user] && conn.assigns[:current_user].id)
    user = Repo.get!(User, user_id)

    # 🛡️ Structural Role Constraint Check: Validate entry authority limits before writing to disk
    if user.is_admin or user.role in [:admin, :moderator] or to_string(user.role) == "Vanguard" or user.is_verified_candidate do
      full_attrs = Map.put(deadline_params, "logged_by_id", user_id)

      %ElectionDeadline{}
      |> ElectionDeadline.changeset(full_attrs)
      |> Repo.insert()
      |> case do
        {:ok, saved_deadline} ->
          conn
          |> put_status(:created)
          |> json(saved_deadline)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Account credentials lack authorized ledger writer status metrics."})
    end
  end
end

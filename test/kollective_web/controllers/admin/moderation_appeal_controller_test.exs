defmodule KollectiveWeb.Admin.ModerationAppealControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Moderation.ModerationAppeal
  alias Kollective.Moderation.Incident

  setup %{conn: conn} do
    user = insert(:user, country: "US")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v1/moderation/appeals" do
    test "creates appeal, dual-writes to Postgres and Mnesia", %{conn: conn, user: user} do
      incident_id = Ecto.ULID.generate()

      {:ok, _incident} =
        %Incident{}
        |> Incident.changeset(%{
          id: incident_id,
          status: "pending",
          country_code: "US",
          origin_node_atom: "node_test@127.0.0.1",
          description: "Appealable incident",
          reporter_id: user.id
        })
        |> Repo.insert()

      appeal_params = %{
        "incident_id" => incident_id,
        "reason" => "I did not violate community standards."
      }

      conn = post(conn, ~p"/api/v1/moderation/appeals", %{"appeal" => appeal_params})

      assert json_response(conn, 200)["status"] == "success"

      # Verify created in Postgres
      appeal = Repo.get_by(ModerationAppeal, incident_id: incident_id, user_id: user.id)
      assert appeal != nil
      assert appeal.status == "pending"
      assert appeal.country_code == "US"

      # Verify created in Mnesia
      {:atomic, [mnesia_record]} =
        :mnesia.transaction(fn -> :mnesia.read(:distributed_appeals, to_string(appeal.id)) end)

      assert Tuple.to_list(mnesia_record) |> Enum.at(1) == to_string(appeal.id)
    end

    test "returns 422 when required fields are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/moderation/appeals", %{"appeal" => %{}})

      assert json_response(conn, 422)["error"] == "Failed to map operational appeal properties."
    end
  end
end

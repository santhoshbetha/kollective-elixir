defmodule KollectiveWeb.Admin.MeshIncidentControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Moderation.Incident

  setup %{conn: conn} do
    # Clear Mnesia table
    if :scholar_incidents in :mnesia.system_info(:tables) do
      :mnesia.clear_table(:scholar_incidents)
    end

    # Moderator with clearance
    moderator = insert(:user, is_moderator: true, badge_type: "moderator", country: "US")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, moderator)
      |> assign(:user, moderator)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, moderator: moderator}
  end

  describe "lease_next/2" do
    test "successfully leases next incident via MeshIncidentController", %{conn: conn} do
      incident_id = Ecto.ULID.generate()
      now = System.system_time(:second)

      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          incident_id,
          "pending",
          "US",
          "offending_actor",
          "Flagged mesh incident",
          now - 30,
          nil,
          nil
        })
      end)

      conn = post(conn, ~p"/api/v1/admin/incidents/lease_next")

      assert %{"data" => ticket} = json_response(conn, 200)
      assert ticket["id"] == incident_id
      assert ticket["status"] == "pending"
      assert ticket["target_username"] == "offending_actor"
    end

    test "returns empty_queue when no tickets available", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/admin/incidents/lease_next")

      assert %{"data" => nil, "status" => "empty_queue"} = json_response(conn, 200)
    end
  end

  describe "claim, release, extend, and resolve lifecycle" do
    test "claims, extends, and resolves incident", %{conn: conn, moderator: moderator} do
      now = System.system_time(:second)
      incident_id = Ecto.ULID.generate()

      # Create in Postgres
      {:ok, incident} =
        %Incident{}
        |> Incident.changeset(%{
          id: incident_id,
          status: "pending",
          country_code: "US",
          origin_node_atom: "node_test@127.0.0.1",
          description: "Mesh test lifecycle incident",
          reporter_id: moderator.id
        })
        |> Repo.insert()

      # Write to Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({
          :scholar_incidents,
          to_string(incident.id),
          "pending",
          "US",
          "target_user",
          "Mesh test lifecycle incident",
          now,
          nil,
          nil
        })
      end)

      # 1. Claim
      conn_claim = post(conn, ~p"/api/v1/admin/incidents/#{incident.id}/claim")
      assert json_response(conn_claim, 200)["status"] == "success"

      # 2. Extend
      conn_extend = post(conn, ~p"/api/v1/admin/incidents/#{incident.id}/extend")
      assert json_response(conn_extend, 200)["status"] == "success"

      # 3. Resolve
      conn_resolve = post(conn, ~p"/api/v1/admin/incidents/#{incident.id}/resolve", %{"action" => "dismiss"})
      assert json_response(conn_resolve, 200) == %{"status" => "success", "final_status" => "resolved_restored"}
    end
  end
end

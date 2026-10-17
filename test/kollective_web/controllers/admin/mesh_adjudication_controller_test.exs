defmodule KollectiveWeb.Admin.MeshAdjudicationControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Moderation.ModerationAppeal
  alias Kollective.Moderation.Incident

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")
    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin, user: user}
  end

  describe "POST /api/v1/admin/moderation_appeals/:id/adjudicate" do
    test "approves appeal and restores underlying incident", %{conn: conn, user: user} do
      incident_id = Ecto.ULID.generate()

      {:ok, incident} =
        %Incident{}
        |> Incident.changeset(%{
          id: incident_id,
          status: "pending",
          country_code: "US",
          origin_node_atom: "node_test@127.0.0.1",
          description: "Incident for appeal",
          reporter_id: user.id
        })
        |> Repo.insert()

      appeal_id = Ecto.ULID.generate()

      {:ok, appeal} =
        %ModerationAppeal{}
        |> ModerationAppeal.changeset(%{
          id: appeal_id,
          incident_id: incident.id,
          user_id: user.id,
          reason: "I was falsely flagged for plagiarism.",
          status: "pending",
          country_code: "US",
          origin_node_atom: Atom.to_string(Node.self())
        })
        |> Repo.insert()

      # Write to Mnesia
      :mnesia.transaction(fn ->
        :mnesia.write({:distributed_appeals, to_string(appeal.id), to_string(incident.id), to_string(user.id), appeal.reason, "pending", "US", "now"})
        :mnesia.write({:scholar_incidents, to_string(incident.id), "pending", "US", "user", "desc", 1234, nil, nil})
      end)

      conn = post(conn, ~p"/api/v1/admin/moderation_appeals/#{appeal.id}/adjudicate", %{
        "resolution" => "approve"
      })

      assert json_response(conn, 200)["status"] == "success"

      # Verify appeal is approved
      updated_appeal = Repo.get!(ModerationAppeal, appeal.id)
      assert updated_appeal.status == "approved"

      # Verify incident is restored
      updated_incident = Repo.get!(Incident, incident.id)
      assert updated_incident.status == "resolved_restored"

      # Verify Mnesia purged records
      assert {:atomic, []} = :mnesia.transaction(fn -> :mnesia.read(:distributed_appeals, to_string(appeal.id)) end)
      assert {:atomic, []} = :mnesia.transaction(fn -> :mnesia.read(:scholar_incidents, to_string(incident.id)) end)
    end

    test "rejects appeal without restoring incident", %{conn: conn, user: user} do
      incident_id = Ecto.ULID.generate()

      {:ok, incident} =
        %Incident{}
        |> Incident.changeset(%{
          id: incident_id,
          status: "pending",
          country_code: "US",
          origin_node_atom: "node_test@127.0.0.1",
          description: "Incident for rejected appeal",
          reporter_id: user.id
        })
        |> Repo.insert()

      appeal_id = Ecto.ULID.generate()

      {:ok, appeal} =
        %ModerationAppeal{}
        |> ModerationAppeal.changeset(%{
          id: appeal_id,
          incident_id: incident.id,
          user_id: user.id,
          reason: "Unjust suspension",
          status: "pending",
          country_code: "US",
          origin_node_atom: Atom.to_string(Node.self())
        })
        |> Repo.insert()

      conn = post(conn, ~p"/api/v1/admin/moderation_appeals/#{appeal.id}/adjudicate", %{
        "resolution" => "reject"
      })

      assert json_response(conn, 200)["status"] == "success"

      updated_appeal = Repo.get!(ModerationAppeal, appeal.id)
      assert updated_appeal.status == "rejected"

      # Incident status should not be changed to restored
      updated_incident = Repo.get!(Incident, incident.id)
      assert updated_incident.status == "pending"
    end

    test "returns error when appeal not found", %{conn: conn} do
      fake_id = Ecto.ULID.generate()

      conn = post(conn, ~p"/api/v1/admin/moderation_appeals/#{fake_id}/adjudicate", %{
        "resolution" => "approve"
      })

      assert json_response(conn, 422)["error"] == "Transaction rolled back."
    end
  end
end

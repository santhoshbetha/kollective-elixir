defmodule KollectiveWeb.JuryVoteControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Voting.{RedBadgeApplication, ApplicationJury}

  setup %{conn: conn} do
    juror = insert(:user)
    applicant = insert(:user)

    app =
      %RedBadgeApplication{}
      |> RedBadgeApplication.changeset(%{
        applicant_id: applicant.id,
        evidence_text: "Journalistic work samples"
      })
      |> Repo.insert!()

    jury_slot =
      %ApplicationJury{}
      |> ApplicationJury.changeset(%{
        application_id: app.id,
        juror_id: juror.id,
        vote: "unvoted"
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, juror)
      |> assign(:user, juror)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, juror: juror, app: app, jury_slot: jury_slot}
  end

  describe "POST /api/v1/voting/applications/:application_id/votes" do
    test "casts ballot successfully", %{conn: conn, app: app, jury_slot: jury_slot} do
      payload = %{"vote" => "approve"}

      conn = post(conn, ~p"/api/v1/voting/applications/#{app.id}/votes", payload)
      assert %{"status" => "success"} = json_response(conn, 200)

      updated_slot = Repo.get!(ApplicationJury, jury_slot.id)
      assert updated_slot.vote == "approve"
      assert updated_slot.voted_at != nil
    end

    test "returns 409 conflict when juror votes twice", %{conn: conn, app: app} do
      # Cast first vote
      post(conn, ~p"/api/v1/voting/applications/#{app.id}/votes", %{"vote" => "approve"})

      # Second vote fails
      conn = post(conn, ~p"/api/v1/voting/applications/#{app.id}/votes", %{"vote" => "reject"})
      assert json_response(conn, 409)["error"] =~ "already cast a ballot"
    end

    test "returns 403 forbidden when user is not an assigned juror", %{conn: conn, app: app} do
      other_user = insert(:user)

      conn =
        conn
        |> assign(:current_user, other_user)
        |> assign(:user, other_user)

      conn = post(conn, ~p"/api/v1/voting/applications/#{app.id}/votes", %{"vote" => "approve"})
      assert json_response(conn, 403)["error"] =~ "not an assigned juror"
    end

    test "returns 422 when vote value is invalid", %{conn: conn, app: app} do
      conn = post(conn, ~p"/api/v1/voting/applications/#{app.id}/votes", %{"vote" => "maybe"})
      assert json_response(conn, 422)["error"] =~ "Invalid ballot value"
    end
  end
end

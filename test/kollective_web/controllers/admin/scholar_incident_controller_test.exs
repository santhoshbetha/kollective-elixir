defmodule KollectiveWeb.Admin.ScholarIncidentControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Repo

  setup %{conn: conn} do
    moderator = insert(:user, is_moderator: true, badge_type: "moderator")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, moderator)
      |> assign(:user, moderator)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, moderator: moderator}
  end

  alias Kollective.Moderation.ScholarIncident

  describe "index/2" do
    test "returns scholar incident list", %{conn: conn} do
      target = insert(:user)

      Repo.insert!(%ScholarIncident{
        status: "pending",
        flag_type: "ORCID_MISMATCH",
        description: "Publication count mismatch",
        user_id: target.id,
        target_username: target.username
      })

      conn = get(conn, ~p"/api/v1/admin/incidents")

      assert %{"data" => incidents} = json_response(conn, 200)
      assert is_list(incidents)
      assert length(incidents) >= 1
    end
  end

  describe "resolve/2" do
    test "resolves incident with restore action", %{conn: conn} do
      target = insert(:user, under_investigation: true)

      incident =
        Repo.insert!(%ScholarIncident{
          status: "pending",
          flag_type: "ORCID_MISMATCH",
          description: "Mismatch description",
          user_id: target.id,
          target_username: target.username
        })

      conn =
        post(conn, ~p"/api/v1/admin/incidents/#{incident.id}/resolve", %{
          "action" => "restore"
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" => "Academic credentials cleared and restored."
             }

      updated_user = Repo.get!(Kollective.Accounts.User, target.id)
      assert updated_user.under_investigation == false
    end

    test "resolves incident with ban action", %{conn: conn} do
      target = insert(:user, under_investigation: true)

      incident =
        Repo.insert!(%ScholarIncident{
          status: "pending",
          flag_type: "ORCID_MISMATCH",
          description: "Mismatch description",
          user_id: target.id,
          target_username: target.username
        })

      conn =
        post(conn, ~p"/api/v1/admin/incidents/#{incident.id}/resolve", %{
          "action" => "ban"
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" => "Prohibited academic profile permanently terminated."
             }

      updated_user = Repo.get!(Kollective.Accounts.User, target.id)
      assert updated_user.badge_type == "suspended"
    end

    test "returns 404 if incident does not exist", %{conn: conn} do
      fake_id = Ecto.ULID.generate()

      conn =
        post(conn, ~p"/api/v1/admin/incidents/#{fake_id}/resolve", %{
          "action" => "restore"
        })

      assert json_response(conn, 404) == %{
               "error" => "Targeted scholar incident record not found."
             }
    end
  end

  describe "security clearance boundary" do
    test "denies access to non-moderator user", %{conn: conn} do
      regular_user = insert(:user, is_admin: false, is_moderator: false, badge_type: "user")

      conn =
        conn
        |> assign(:current_user, regular_user)
        |> assign(:user, regular_user)

      conn = get(conn, ~p"/api/v1/admin/incidents")

      assert json_response(conn, 403) == %{
               "error" => "Access denied: Unauthorized operations clearance level."
             }
    end
  end
end

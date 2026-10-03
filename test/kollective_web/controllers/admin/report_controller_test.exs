defmodule KollectiveWeb.Admin.ReportControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Moderation.Report

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "admin")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "index/2" do
    test "lists compliance reports", %{conn: conn} do
      reporter = insert(:user)
      post = insert(:post)

      Repo.insert!(%Report{
        reason: "harassment",
        details: "Needs review",
        status: "pending",
        reporter_id: reporter.id,
        post_id: post.id
      })

      conn = get(conn, ~p"/api/v1/admin/reports", %{"status" => "pending"})

      assert %{"status" => "success", "data" => reports} = json_response(conn, 200)
      assert is_list(reports)
      assert length(reports) >= 1
    end
  end

  describe "show/2" do
    test "fetches single report detail", %{conn: conn} do
      reporter = insert(:user)
      post = insert(:post)

      report =
        Repo.insert!(%Report{
          reason: "spam",
          details: "Repeated posts",
          status: "pending",
          reporter_id: reporter.id,
          post_id: post.id
        })

      conn = get(conn, ~p"/api/v1/admin/reports/#{report.id}")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["data"]["id"] == to_string(report.id)
      assert response["data"]["status"] == "pending"
    end

    test "returns 404 if report not found", %{conn: conn} do
      fake_id = Ecto.ULID.generate()
      conn = get(conn, ~p"/api/v1/admin/reports/#{fake_id}")

      assert json_response(conn, 404) == %{
               "status" => "error",
               "error" => "ticket_not_found",
               "message" => "Compliance report record does not exist."
             }
    end
  end

  describe "resolve/2" do
    test "resolves a report with action", %{conn: conn} do
      reporter = insert(:user)
      post = insert(:post)

      report =
        Repo.insert!(%Report{
          reason: "inappropriate",
          details: "Please check",
          status: "pending",
          reporter_id: reporter.id,
          post_id: post.id
        })

      conn =
        post(conn, ~p"/api/v1/admin/reports/#{report.id}/resolve", %{
          "action" => "dismiss",
          "notes" => "Dismissed as false positive"
        })

      assert json_response(conn, 200) == %{
               "status" => "success",
               "message" => "Report successfully resolved and actions filed."
             }

      updated_report = Repo.get!(Report, report.id)
      assert updated_report.status == "dismissed"
    end
  end
end

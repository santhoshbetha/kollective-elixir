defmodule KollectiveWeb.Admin.LogControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Admins.Log

  setup %{conn: conn} do
    id1 = System.unique_integer([:positive])

    admin =
      insert(:user,
        role: :admin,
        is_admin: true,
        email: "gov_admin_#{id1}@test.com",
        username: "gov_admin_#{id1}",
        identity_hash: "hash_#{id1}"
      )

    log1 =
      %Log{}
      |> Log.changeset(%{
        action: "event_cancelled",
        target_id: Ecto.ULID.generate(),
        target_type: "Event",
        user_id: admin.id,
        metadata: %{"reason" => "Terms violation"}
      })
      |> Repo.insert!()

    log2 =
      %Log{}
      |> Log.changeset(%{
        action: "post_deleted",
        target_id: Ecto.ULID.generate(),
        target_type: "Post",
        user_id: admin.id,
        metadata: %{"reason" => "Spam"}
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin, log1: log1, log2: log2}
  end

  describe "GET /api/v1/admin/governance_logs" do
    test "lists recent governance logs", %{conn: conn, log1: log1, log2: log2} do
      conn = get(conn, ~p"/api/v1/admin/governance_logs")

      assert %{"status" => "success", "data" => data} = json_response(conn, 200)
      assert is_list(data)

      ids = Enum.map(data, & &1["id"])
      assert log1.id in ids
      assert log2.id in ids
    end

    test "filters logs by action", %{conn: conn, log1: log1, log2: log2} do
      conn = get(conn, ~p"/api/v1/admin/governance_logs", %{"filters" => %{"action" => "event_cancelled"}})

      assert %{"status" => "success", "data" => data} = json_response(conn, 200)
      assert is_list(data)

      ids = Enum.map(data, & &1["id"])
      assert log1.id in ids
      refute log2.id in ids
    end
  end
end

defmodule KollectiveWeb.Admin.ScholarControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.User

  setup %{conn: conn} do
    id1 = System.unique_integer([:positive])
    id2 = System.unique_integer([:positive])

    admin =
      insert(:user,
        role: :admin,
        is_admin: true,
        email: "admin_scholar_#{id1}@test.com",
        username: "admin_scholar_#{id1}",
        identity_hash: "hash_#{id1}"
      )

    penalized_user =
      insert(:user,
        type: :citizen,
        badge_type: "ClassicBlue",
        email: "penalized_#{id2}@test.com",
        username: "penalized_#{id2}",
        identity_hash: "hash_#{id2}"
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin, penalized_user: penalized_user}
  end

  describe "POST /api/v1/admin/incidents/users/:user_id/restore" do
    test "successfully reinstates penalized user to scholar status", %{
      conn: conn,
      admin: admin,
      penalized_user: user
    } do
      conn = post(conn, ~p"/api/v1/admin/incidents/users/#{user.id}/restore")

      assert %{
               "status" => "success",
               "message" => msg,
               "data" => %{
                 "user_id" => user_id,
                 "type" => "scholar",
                 "badge_type" => "verified_scholar",
                 "reinstated_by_admin" => admin_id
               }
             } = json_response(conn, 200)

      assert msg =~ "reinstated to Scholar tier"
      assert user_id == to_string(user.id)
      assert admin_id == to_string(admin.id)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.type == :scholar
      assert updated_user.badge_type == "verified_scholar"
    end

    test "returns 404 when targeted user does not exist", %{conn: conn} do
      fake_id = Ecto.ULID.generate()
      conn = post(conn, ~p"/api/v1/admin/incidents/users/#{fake_id}/restore")

      assert %{"error" => "user_not_found"} = json_response(conn, 404)
    end
  end
end

defmodule KollectiveWeb.AdminUserControllerTest do
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
        email: "admin_user_#{id1}@test.com",
        username: "admin_usr_#{id1}",
        identity_hash: "hash_admin_#{id1}"
      )

    regular_user =
      insert(:user,
        is_admin: false,
        email: "regular_user_#{id2}@test.com",
        username: "target_voter_#{id2}",
        identity_hash: "hash_user_#{id2}"
      )

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: authed_conn, admin: admin, regular_user: regular_user}
  end

  describe "GET /api/v1/admin/users/search" do
    test "searches users by username query and returns serialized user items", %{
      conn: conn,
      regular_user: user
    } do
      res =
        conn
        |> get(~p"/api/v1/admin/users/search", %{"q" => "target_voter"})
        |> json_response(200)

      assert is_list(res["data"])
      assert Enum.any?(res["data"], fn item -> item["id"] == user.id end)
    end

    test "works via /api/admin/users/search legacy path", %{
      conn: conn,
      regular_user: user
    } do
      res =
        conn
        |> get(~p"/api/admin/users/search", %{"q" => user.username})
        |> json_response(200)

      assert is_list(res["data"])
      assert Enum.any?(res["data"], fn item -> item["id"] == user.id end)
    end

    test "rejects unauthorized non-admin access", %{regular_user: non_admin} do
      unauthed_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> assign(:current_user, non_admin)
        |> assign(:user, non_admin)

      res =
        unauthed_conn
        |> get(~p"/api/v1/admin/users/search", %{"q" => "test"})
        |> json_response(403)

      assert res["code"] == "unauthorized_access"
    end
  end

  describe "PUT /api/v1/admin/users/:id/override-districts" do
    test "successfully updates user political districts and city", %{
      conn: conn,
      regular_user: user
    } do
      d1 = insert(:political_district, level: 1, state: "CA")
      d2 = insert(:political_district, level: 2, state: "CA")
      d3 = insert(:political_district, level: 3, state: "CA")
      city = insert(:city, state: "CA")

      payload = %{
        "override" => %{
          "district_l1_id" => d1.id,
          "district_l2_id" => d2.id,
          "district_l3_id" => d3.id,
          "city_id" => city.id
        }
      }

      res =
        conn
        |> put(~p"/api/v1/admin/users/#{user.id}/override-districts", payload)
        |> json_response(200)

      assert res["status"] == "success"
      assert res["user_id"] == user.id

      updated = Repo.get!(User, user.id)
      assert updated.district_l1_id == d1.id
      assert updated.district_l2_id == d2.id
      assert updated.district_l3_id == d3.id
      assert updated.city_id == city.id
    end

    test "returns 422 if validation fails on street address without complete district stack", %{
      conn: conn,
      regular_user: user
    } do
      # Set a street address on user first
      user
      |> Ecto.Changeset.change(%{street_address: "123 Main St"})
      |> Repo.update!()

      payload = %{
        "override" => %{
          "district_l1_id" => nil,
          "district_l2_id" => nil,
          "district_l3_id" => nil
        }
      }

      res =
        conn
        |> put(~p"/api/v1/admin/users/#{user.id}/override-districts", payload)
        |> json_response(422)

      assert res["errors"]["district_l1_id"] != nil
    end
  end
end

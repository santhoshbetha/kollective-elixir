defmodule KollectiveWeb.Admin.VouchBootstrapControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Accounts.User

  setup %{conn: conn} do
    # Create the authenticated admin user (must have role: :admin)
    admin = insert(:user, role: :admin)
    conn = authenticate_conn(conn, admin)

    {:ok, conn: conn, admin: admin}
  end

  describe "bootstrap_seed/2" do
    test "successfully elevates target user to tier 1 when requirements are met", %{conn: conn} do
      district = insert(:political_district, state: "CA")

      target_user =
        insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: district.id)

      conn = post(conn, ~p"/api/v1/admin/civic/bootstrap-seed", %{"user_id" => target_user.id})

      assert %{
               "status" => "success",
               "message" =>
                 "Seed Node status assigned. User can now organically verify overlapping neighbors.",
               "data" => %{
                 "user_id" => user_id_str,
                 "account_tier" => 1
               }
             } = json_response(conn, 200)

      assert user_id_str == target_user.id

      # Verify database values updated
      updated_user = Kollective.Repo.get!(User, target_user.id)
      assert updated_user.account_tier == 1
      assert updated_user.metadata["bootstrapped_via_video_at"]
    end

    test "fails with conflict (409) if user does not have location district metrics", %{
      conn: conn
    } do
      # User with nil district
      target_user = insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: nil)

      conn = post(conn, ~p"/api/v1/admin/civic/bootstrap-seed", %{"user_id" => target_user.id})

      assert json_response(conn, 409) == %{
               "status" => "error",
               "error" =>
                 "User profiles must contain verified district metrics before initialization."
             }
    end

    test "fails with conflict (409) if the sector already has 3 seed nodes", %{conn: conn} do
      district = insert(:political_district, state: "CA")

      # Set up 3 existing seed nodes in the CA / Senate District 1 sector
      insert(:user, account_tier: 1, origin_state: "CA", district_l1_id: district.id)
      insert(:user, account_tier: 1, origin_state: "CA", district_l1_id: district.id)
      insert(:user, account_tier: 1, origin_state: "CA", district_l1_id: district.id)

      # Try to seed a 4th user
      target_user =
        insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: district.id)

      conn = post(conn, ~p"/api/v1/admin/civic/bootstrap-seed", %{"user_id" => target_user.id})

      assert json_response(conn, 409) == %{
               "status" => "error",
               "error" =>
                 "This overlapping boundary sector has already established 3 seed nodes. Use P2P network instead."
             }
    end

    test "denies access to non-admin users", %{conn: conn} do
      # Replace connection assigns with a standard user profile (role: :user)
      non_admin = insert(:user, role: :user)
      conn = authenticate_conn(conn, non_admin)

      district = insert(:political_district, state: "CA")

      target_user =
        insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: district.id)

      conn = post(conn, ~p"/api/v1/admin/civic/bootstrap-seed", %{"user_id" => target_user.id})

      assert json_response(conn, 403) == %{
               "error" => "Access Denied: Administrative privileges are strictly required."
             }
    end
  end
end

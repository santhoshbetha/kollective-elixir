defmodule KollectiveWeb.VouchControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Ecto.Query
  import Kollective.Factory

  alias Kollective.Civic.VouchCache
  alias Kollective.Civic.Vouch

  setup %{conn: conn} do
    # Create a political district
    district = insert(:political_district, state: "CA")

    # Create the authenticated voucher (must be tier 1)
    voucher = insert(:user, account_tier: 1, origin_state: "CA", district_l1_id: district.id)
    conn = authenticate_conn(conn, voucher)

    {:ok, conn: conn, voucher: voucher, district: district}
  end

  describe "request_token/2" do
    test "generates a temporary secure scan token for the current user", %{
      conn: conn,
      voucher: voucher
    } do
      conn = post(conn, ~p"/api/v1/vouch/generate-token")

      assert %{
               "status" => "success",
               "secure_token" => secure_token
             } = json_response(conn, 200)

      assert is_binary(secure_token)
      assert String.starts_with?(secure_token, "vouch_tmp_")

      # Verify it resolved and saved in the Cachex store correctly
      assert {:ok, vouchee_id} = VouchCache.consume_token(secure_token)
      assert vouchee_id == voucher.id
    end
  end

  describe "execute_peer_vouch/2" do
    test "successfully processes a peer vouch, inserts signature and returns count", %{
      conn: conn,
      voucher: voucher,
      district: district
    } do
      # 1. Create a vouchee user sharing CA state and Senate District 1
      vouchee = insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: district.id)

      # 2. Generate a token for this vouchee
      token = VouchCache.generate_token(vouchee.id)

      # 3. Post to verify-peer
      conn = post(conn, ~p"/api/v1/vouch/verify-peer", %{"secure_token" => token})

      assert json_response(conn, 200) == %{
               "status" => "success",
               "current_vouches" => 1
             }

      # 4. Verify DB signature exists
      assert Kollective.Repo.exists?(
               from(v in Vouch,
                 where: v.voucher_id == ^voucher.id and v.vouchee_id == ^vouchee.id
               )
             )
    end

    test "fails with gone (410) if the token is expired or not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/vouch/verify-peer", %{"secure_token" => "vouch_tmp_non_existent"})

      assert json_response(conn, 400) == %{
               "status" => "error",
               "error" => "token_invalid",
               "message" => "Invalid or already consumed token signature."
             }
    end

    test "fails with unprocessable entity (422) if verification guards fail", %{
      conn: conn,
      voucher: voucher
    } do
      # Create a vouchee user in a different state (or district)
      ny_district = insert(:political_district, state: "NY")
      vouchee = insert(:user, account_tier: 0, origin_state: "NY", district_l1_id: ny_district.id)
      token = VouchCache.generate_token(vouchee.id)

      conn = post(conn, ~p"/api/v1/vouch/verify-peer", %{"secure_token" => token})

      assert %{
               "status" => "error",
               "error" => "transaction_failed",
               "message" => "Cross-state validation mapping rejected."
             } = json_response(conn, 422)
    end

    test "AccountJSON serializes vouch_count calculated directly from user_vouches database table", %{
      voucher: voucher,
      district: district
    } do
      vouchee = insert(:user, account_tier: 0, origin_state: "CA", district_l1_id: district.id)
      assert KollectiveWeb.AccountJSON.show(%{user: vouchee}).vouch_count == 0

      insert(:vouch, voucher: voucher, vouchee: vouchee, origin_state: "CA", matched_tier: "l1", district_value: district.id)

      rendered = KollectiveWeb.AccountJSON.show(%{user: vouchee})
      assert rendered.vouch_count == 1
      assert rendered.account_tier == 0
    end
  end
end

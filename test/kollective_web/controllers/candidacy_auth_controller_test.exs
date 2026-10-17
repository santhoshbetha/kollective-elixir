defmodule KollectiveWeb.CandidacyAuthControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.User
  alias Kollective.Campaigns.CandidacyApplication

  setup %{conn: conn} do
    u = fn attrs ->
      id = System.unique_integer([:positive])
      insert(:user, Map.merge(%{
        email: "candidacy_#{id}@test.com",
        username: "cand_#{id}",
        identity_hash: "hash_#{id}"
      }, Map.new(attrs)))
    end

    candidate = u.(state: "TX")
    voucher1 = u.(state: "TX")
    voucher2 = u.(state: "TX")
    voucher3 = u.(state: "TX")
    out_of_state_user = u.(state: "CA")
    admin_user = u.(role: :admin, is_admin: true)

    app =
      %CandidacyApplication{}
      |> CandidacyApplication.changeset(%{
        user_id: candidate.id,
        declared_profession: "Electrician",
        employment_proof_url: "https://proof.example.com/id.jpg",
        status: "pending_vouches",
        vouches_count: 0
      })
      |> Repo.insert!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:is_authenticated, true)

    {:ok,
     conn: conn,
     candidate: candidate,
     voucher1: voucher1,
     voucher2: voucher2,
     voucher3: voucher3,
     out_of_state_user: out_of_state_user,
     admin_user: admin_user,
     app: app}
  end

  describe "POST /api/v1/campaigns/apply/vouch" do
    test "allows constituent from same state to cast a vouch", %{
      conn: conn,
      voucher1: voucher1,
      app: app
    } do
      conn =
        conn
        |> assign(:current_user, voucher1)
        |> assign(:user, voucher1)
        |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      assert %{"vouches_count" => 1, "status" => "pending_vouches"} = json_response(conn, 200)

      updated_app = Repo.get!(CandidacyApplication, app.id)
      assert updated_app.vouches_count == 1
    end

    test "rejects vouch when user tries to vouch for themselves", %{
      conn: conn,
      candidate: candidate,
      app: app
    } do
      conn =
        conn
        |> assign(:current_user, candidate)
        |> assign(:user, candidate)
        |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      assert json_response(conn, 400)["error"] == "cannot_vouch_for_self"
    end

    test "rejects vouch when user resides in a different state", %{
      conn: conn,
      out_of_state_user: out_of_state_user,
      app: app
    } do
      conn =
        conn
        |> assign(:current_user, out_of_state_user)
        |> assign(:user, out_of_state_user)
        |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      assert json_response(conn, 400)["error"] == "must_reside_in_same_state"
    end

    test "rejects duplicate vouch from same constituent", %{
      conn: conn,
      voucher1: voucher1,
      app: app
    } do
      conn1 =
        conn
        |> assign(:current_user, voucher1)
        |> assign(:user, voucher1)

      conn1 |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      conn2 =
        conn
        |> assign(:current_user, voucher1)
        |> assign(:user, voucher1)
        |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      assert json_response(conn2, 400)["error"] == "already_vouch_signed"
    end

    test "automatically advances to under_jury_review after 3 vouches", %{
      conn: conn,
      voucher1: voucher1,
      voucher2: voucher2,
      voucher3: voucher3,
      app: app
    } do
      conn |> assign(:current_user, voucher1) |> assign(:user, voucher1) |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})
      conn |> assign(:current_user, voucher2) |> assign(:user, voucher2) |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      conn3 =
        conn
        |> assign(:current_user, voucher3)
        |> assign(:user, voucher3)
        |> post(~p"/api/v1/campaigns/apply/vouch", %{"application_id" => app.id})

      assert %{"vouches_count" => 3, "status" => "under_jury_review"} = json_response(conn3, 200)

      updated_app = Repo.get!(CandidacyApplication, app.id)
      assert updated_app.status == "under_jury_review"
    end
  end

  describe "POST /api/v1/campaigns/apply/approve" do
    test "authorized admin can approve application and promote candidate", %{
      conn: conn,
      admin_user: admin_user,
      candidate: candidate,
      app: app
    } do
      conn =
        conn
        |> assign(:current_user, admin_user)
        |> assign(:user, admin_user)
        |> post(~p"/api/v1/campaigns/apply/approve", %{"id" => app.id})

      assert %{"message" => message} = json_response(conn, 200)
      assert message =~ "Citizen candidacy portfolio approved"

      updated_app = Repo.get!(CandidacyApplication, app.id)
      assert updated_app.status == "approved"

      updated_user = Repo.get!(User, candidate.id)
      assert updated_user.is_candidate == true
      assert updated_user.is_verified_candidate == true
    end

    test "rejects approval attempt from non-admin user", %{
      conn: conn,
      voucher1: voucher1,
      app: app
    } do
      conn =
        conn
        |> assign(:current_user, voucher1)
        |> assign(:user, voucher1)
        |> post(~p"/api/v1/campaigns/apply/approve", %{"id" => app.id})

      assert json_response(conn, 401)["error"] =~ "Action restricted to Vanguard panel members"
    end
  end
end

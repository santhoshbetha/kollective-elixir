defmodule KollectiveWeb.ScholarControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Repo
  alias Kollective.Accounts.User

  setup %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:user, user)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v1/scholar-verify" do
    test "verifies scholar credentials with valid ORCID iD", %{conn: conn, user: user} do
      payload = %{
        "orcid_id" => "0000-0002-1825-0001"
      }

      conn = post(conn, ~p"/api/v1/scholar-verify", payload)
      assert %{"status" => "success"} = json_response(conn, 200)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.badge_type == "Scholar"
    end

    test "returns 422 when ORCID string format is invalid", %{conn: conn} do
      payload = %{
        "orcid_id" => "1234-invalid-orcid"
      }

      conn = post(conn, ~p"/api/v1/scholar-verify", payload)
      assert json_response(conn, 422)["error"] == "malformed_format"
    end
  end
end

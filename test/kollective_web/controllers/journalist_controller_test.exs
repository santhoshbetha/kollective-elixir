defmodule KollectiveWeb.JournalistControllerTest do
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

  describe "POST /api/v1/journalist-verify" do
    test "authenticates credentials with valid muckrack URL", %{conn: conn, user: user} do
      payload = %{
        "portfolio_url" => "https://muckrack.com/alice-reporter"
      }

      conn = post(conn, ~p"/api/v1/journalist-verify", payload)
      assert %{"status" => "success"} = json_response(conn, 200)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.badge_type == "ProfessionalTeal"
    end

    test "returns 400 when portfolio URL is not a recognized registry", %{conn: conn} do
      payload = %{
        "portfolio_url" => "https://myblog.example.com/posts"
      }

      conn = post(conn, ~p"/api/v1/journalist-verify", payload)
      assert json_response(conn, 400)["error"] =~ "does not map to an active portfolio"
    end

    test "returns 422 when URL format is malformed", %{conn: conn} do
      payload = %{
        "portfolio_url" => "ftp://muckrack.com/alice"
      }

      conn = post(conn, ~p"/api/v1/journalist-verify", payload)
      assert json_response(conn, 422)["error"] =~ "Malformed media URL structure"
    end
  end
end

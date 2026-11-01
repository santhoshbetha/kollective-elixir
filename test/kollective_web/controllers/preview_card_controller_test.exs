defmodule KollectiveWeb.PreviewCardControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  setup %{conn: conn} do
    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "POST /api/v1/preview_cards/fetch" do
    test "rejects invalid or unsupported URL schemes", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/preview_cards/fetch", %{"url" => "ftp://invalid-scheme.com"})
      assert json_response(conn, 400)["error"] =~ "Only http and https"
    end

    test "rejects empty or missing URL parameter", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/preview_cards/fetch", %{})
      assert json_response(conn, 400)["error"] =~ "Missing or invalid URL"
    end

    test "returns fallback preview card map when host cannot be reached or timeout occurs", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/preview_cards/fetch", %{"url" => "http://127.0.0.1:59999/nonexistent"})
      res = json_response(conn, 200)

      assert res["domain"] == "127.0.0.1"
      assert res["preview_card"]["domain"] == "127.0.0.1"
      assert res["preview_card"]["id"] =~ "card-"
    end
  end
end


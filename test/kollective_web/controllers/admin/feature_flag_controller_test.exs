defmodule KollectiveWeb.Admin.FeatureFlagControllerTest do
  use KollectiveWeb.ConnCase, async: false
  import Kollective.Factory

  alias Kollective.Admin.FeatureFlags

  setup %{conn: conn} do
    admin = insert(:user, is_admin: true, is_moderator: true, badge_type: "moderator")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, admin)
      |> assign(:user, admin)
      |> assign(:is_authenticated, true)

    {:ok, conn: conn, admin: admin}
  end

  describe "FeatureFlagController index" do
    test "lists all system feature flags", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/config/feature_flags")
      assert %{"data" => flags} = json_response(conn, 200)
      assert is_list(flags)
    end

    test "blocks unprivileged users with 403 Forbidden", %{conn: conn} do
      regular_user = insert(:user, is_admin: false, is_moderator: false, badge_type: "member")

      conn =
        conn
        |> assign(:current_user, regular_user)
        |> assign(:user, regular_user)

      conn = get(conn, ~p"/api/v1/admin/config/feature_flags")
      assert json_response(conn, 403)["error"] =~ "Access denied"
    end
  end

  describe "FeatureFlagController toggle" do
    test "toggles feature flag value", %{conn: conn} do
      payload = %{
        "key" => "registration_open",
        "enabled" => false
      }

      conn = post(conn, ~p"/api/v1/admin/config/feature_flags/toggle", payload)
      assert %{"data" => data} = json_response(conn, 200)
      assert data["key"] == "registration_open"
      assert data["enabled"] == false
      assert FeatureFlags.enabled?("registration_open") == false

      # Reset back
      FeatureFlags.toggle_flag("registration_open", true)
    end

    test "returns 400 when missing key or enabled boolean", %{conn: conn} do
      payload = %{
        "key" => "registration_open"
      }

      conn = post(conn, ~p"/api/v1/admin/config/feature_flags/toggle", payload)
      assert json_response(conn, 400)["error"] =~ "Missing required parameters"
    end
  end
end

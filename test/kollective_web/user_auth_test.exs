defmodule KollectiveWeb.UserAuthTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Accounts.Scope
  alias KollectiveWeb.UserAuth

  import Kollective.AccountsFixtures

  setup %{conn: conn} do
    %{user: user_fixture(), conn: conn}
  end

  describe "fetch_current_scope_for_user/2 - JSON API Bearer Token" do
    test "authenticates user from current_user assign", %{conn: conn, user: user} do
      conn =
        conn
        # 💡 Seed current_user so fetch_current_scope_for_user loads correctly
        |> assign(:current_user, user)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
    end

    test "assigns empty scope when no current_user", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope == nil
    end
  end

  describe "require_sudo_mode/2" do
    test "allows users that have authenticated in the last 10 minutes", %{conn: conn, user: user} do
      # 💡 Ensure both fields are set dynamically to mirror real endpoints
      user = %{user | authenticated_at: DateTime.utc_now()}

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_sudo_mode([])

      refute conn.halted
    end

    test "returns forbidden when authentication is too old", %{conn: conn, user: user} do
      eleven_minutes_ago = DateTime.utc_now() |> DateTime.add(-11, :minute)
      user = %{user | authenticated_at: eleven_minutes_ago}

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_sudo_mode([])

      assert conn.halted
      assert conn.status == 403
      assert json_response(conn, 403)["error"]
    end
  end

  describe "redirect_if_user_is_authenticated/2 - JSON API" do
    test "returns 403 if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert conn.status == 403
      assert json_response(conn, 403)["error"] =~ "already logged in"
    end

    test "does not halt if user is not authenticated", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(nil))
        |> UserAuth.redirect_if_user_is_authenticated([])

      refute conn.halted
    end
  end

  describe "require_authenticated_user/2 - JSON API" do
    test "returns 401 if user is not authenticated", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(nil))
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "does not halt if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end
  end
end

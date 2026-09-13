defmodule KollectiveWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KollectiveWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint KollectiveWeb.Endpoint

      use KollectiveWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import KollectiveWeb.ConnCase
    end
  end

  setup tags do
    Kollective.DataCase.setup_sandbox(tags)
    ip_part1 = rem(System.unique_integer([:positive]), 250) + 1
    ip_part2 = rem(System.unique_integer([:positive]), 250) + 1

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:remote_ip, {10, 99, ip_part1, ip_part2})

    {:ok, conn: conn}
  end

  @doc """
  @doc \"""
  Setup helper that creates an authenticated user and assigns them to the connection.

      setup :authenticate_user

  It stores an updated connection and a registered user in the
  test context with Bearer token authorization.
  """
  def authenticate_user(%{conn: conn}) do
    user = Kollective.AccountsFixtures.user_fixture()
    token = Kollective.Accounts.Accounts.generate_user_session_token(user)

    authenticated_conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> Plug.Conn.assign(:current_user, user)

    scope = Kollective.Accounts.Scope.for_user(user)
    %{conn: authenticated_conn, user: user, scope: scope, token: token}
  end

  @doc """
  Adds Bearer token authorization to a connection for the given user.

  It returns an updated connection with the Authorization header set.
  """
  def authenticate_conn(conn, user) do
    token = Kollective.Accounts.Accounts.generate_user_session_token(user)

    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.assign(:current_user, user)
  end
end

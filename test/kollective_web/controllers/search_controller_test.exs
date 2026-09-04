defmodule KollectiveWeb.SearchControllerTest do
  use KollectiveWeb.ConnCase, async: true

  alias Kollective.Repo
  alias Kollective.Accounts.User

  setup %{conn: conn} do
    user =
      %User{
        email: "tester@kollective.org",
        username: "testuser"
      }
      |> Repo.insert!()

    conn = assign(conn, :current_user, user)

    {:ok, conn: conn, user: user}
  end

  describe "GET /api/v1/search (Unified Endpoint)" do
    test "returns empty layout maps when query string is too short", %{conn: conn} do
      for invalid_q <- [nil, "", "a", "ab"] do
        res =
          conn
          |> get(~p"/api/v1/search", q: invalid_q)
          |> json_response(200)

        assert res == %{
                 "posts" => %{"results" => []},
                 "accounts" => [],
                 "hashtags" => [],
                 "events" => []
               }
      end
    end

    test "hashtags preprocessing normalizes input strings and strips full URIs", %{conn: conn} do
      # Insert raw record directly into DB sandbox matching the expected downcased format
      %Kollective.Hashtags.Hashtag{name: "elixir"} |> Repo.insert!()

      # 🛡️ FIX: URL-encode the '#' symbol manually or via URI.encode_www_form/1
      # This guarantees that the controller receives the string chunk containing the hashtag
      encoded_query = "https://kollective.org" <> URI.encode_www_form("#elixir")

      res =
        conn
        |> get(~p"/api/v1/search", q: encoded_query, type: "hashtags")
        |> json_response(200)

      assert [%{"name" => "elixir", "url" => url}] = res["hashtags"]
      assert String.contains?(url, "/api/discovery/hashtag?tag=elixir")
    end
  end

  describe "GET /api/v1/search/accounts" do
    test "executes query pipeline and returns matches", %{conn: conn} do
      %User{email: "alice@kollective.org", username: "alice_indie"} |> Repo.insert!()

      res =
        conn
        |> get(~p"/api/v1/search/accounts", q: "alice")
        |> json_response(200)

      assert res["status"] == "success"
      assert is_list(res["accounts"])
    end
  end
end

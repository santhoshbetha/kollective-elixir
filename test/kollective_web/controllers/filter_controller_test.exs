defmodule KollectiveWeb.FilterControllerTest do
  use KollectiveWeb.ConnCase, async: true
  import Kollective.Factory

  alias Kollective.Posts.UserFilter
  alias Kollective.Repo

  setup %{conn: conn} do
    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user, unauthenticated_conn: conn}
  end

  describe "unauthenticated filter endpoints" do
    test "GET /api/v1/filters returns 401 when unauthenticated", %{unauthenticated_conn: conn} do
      conn = get(conn, ~p"/api/v1/filters")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "POST /api/v1/filters returns 401 when unauthenticated", %{unauthenticated_conn: conn} do
      conn = post(conn, ~p"/api/v1/filters", %{"filter" => %{"phrase" => "test"}})

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end

    test "DELETE /api/v1/filters/:id returns 401 when unauthenticated", %{
      unauthenticated_conn: conn
    } do
      conn = delete(conn, ~p"/api/v1/filters/#{Ecto.ULID.generate()}")

      assert conn.status == 401
      assert json_response(conn, 401)["message"] =~ "must log in"
    end
  end

  describe "GET /api/v1/filters" do
    test "returns empty list when user has no active filters", %{conn: conn} do
      response =
        conn
        |> get(~p"/api/v1/filters")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["data"] == []
    end

    test "returns list of active filters belonging to the current user", %{conn: conn, user: user} do
      _filter1 = insert(:user_filter, user: user, phrase: "politics")
      _filter2 = insert(:user_filter, user: user, phrase: "spoilers")

      other_user = insert(:user)
      _other_filter = insert(:user_filter, user: other_user, phrase: "other_user_filter")

      _expired_filter =
        insert(:user_filter,
          user: user,
          phrase: "expired_phrase",
          expires_at:
            DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
        )

      response =
        conn
        |> get(~p"/api/v1/filters")
        |> json_response(200)

      assert response["status"] == "success"
      phrases = Enum.map(response["data"], & &1["phrase"])

      assert "politics" in phrases
      assert "spoilers" in phrases
      refute "other_user_filter" in phrases
      refute "expired_phrase" in phrases
    end
  end

  describe "POST /api/v1/filters" do
    test "creates a new mute phrase filter with default settings", %{conn: conn, user: user} do
      params = %{
        "filter" => %{
          "phrase" => "unwanted_keyword",
          "whole_word" => true,
          "context" => ["home", "public"]
        }
      }

      response =
        conn
        |> post(~p"/api/v1/filters", params)
        |> json_response(201)

      assert response["status"] == "success"
      data = response["data"]
      assert data["phrase"] == "unwanted_keyword"
      assert data["whole_word"] == true
      assert data["context"] == ["home", "public"]
      assert data["expires_at"] == nil
      assert is_binary(data["id"])

      # Verify record exists in database
      filter_record = Repo.get_by(UserFilter, phrase: "unwanted_keyword", user_id: user.id)
      assert filter_record != nil
    end

    test "creates a new filter with relative expires_in duration", %{conn: conn, user: user} do
      params = %{
        "filter" => %{
          "phrase" => "temporary_mute",
          "expires_in" => 3600
        }
      }

      response =
        conn
        |> post(~p"/api/v1/filters", params)
        |> json_response(201)

      assert response["status"] == "success"
      data = response["data"]
      assert data["phrase"] == "temporary_mute"
      assert data["expires_at"] != nil

      filter_record = Repo.get_by(UserFilter, phrase: "temporary_mute", user_id: user.id)
      assert filter_record.expires_at != nil
    end

    test "returns 422 when phrase is missing or empty", %{conn: conn} do
      params = %{
        "filter" => %{
          "phrase" => "",
          "whole_word" => true
        }
      }

      response =
        conn
        |> post(~p"/api/v1/filters", params)
        |> json_response(422)

      assert response["errors"] != nil
    end

    test "returns 422 when phrase is a duplicate for the same user", %{conn: conn, user: user} do
      insert(:user_filter, user: user, phrase: "duplicate_phrase")

      params = %{
        "filter" => %{
          "phrase" => "duplicate_phrase"
        }
      }

      response =
        conn
        |> post(~p"/api/v1/filters", params)
        |> json_response(422)

      assert response["errors"] != nil
    end
  end

  describe "DELETE /api/v1/filters/:id" do
    test "deletes an existing filter belonging to the current user", %{conn: conn, user: user} do
      filter = insert(:user_filter, user: user)

      response =
        conn
        |> delete(~p"/api/v1/filters/#{filter.id}")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] == "Mute phrase successfully removed."

      assert Repo.get(UserFilter, filter.id) == nil
    end

    test "returns 404 when filter ID does not exist", %{conn: conn} do
      missing_id = Ecto.ULID.generate()

      response =
        conn
        |> delete(~p"/api/v1/filters/#{missing_id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["error"] == "Filter parameter not found."
    end

    test "returns 404 when attempting to delete another user's filter", %{conn: conn} do
      other_user = insert(:user)
      other_filter = insert(:user_filter, user: other_user)

      response =
        conn
        |> delete(~p"/api/v1/filters/#{other_filter.id}")
        |> json_response(404)

      assert response["status"] == "error"
      assert response["error"] == "Filter parameter not found."
      assert Repo.get(UserFilter, other_filter.id) != nil
    end
  end
end

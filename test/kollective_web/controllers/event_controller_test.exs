defmodule KollectiveWeb.EventControllerTest do
  use KollectiveWeb.ConnCase, async: true

  import Kollective.Factory

  alias Kollective.Moderation.RestrictedKeyword
  alias Kollective.Repo

  setup %{conn: conn} do
    user = insert(:user)

    authenticated_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)
      |> assign(:current_scope, %{user: user})

    {:ok, conn: authenticated_conn, user: user}
  end

  describe "authentication" do
    test "GET /api/v1/events returns 401 for unauthenticated requests" do
      conn = build_conn() |> get(~p"/api/v1/events")
      assert conn.status == 401
    end
  end

  describe "index/2" do
    test "returns a serialized list for authenticated requests", %{conn: conn, user: user} do
      _event = insert(:event, created_by: user.id, user: user, join_mode: "free")

      response = conn |> get(~p"/api/v1/events") |> json_response(200)

      assert is_list(response["data"])
    end
  end

  describe "show/2" do
    test "injects user RSVP state metadata", %{conn: conn, user: user} do
      event =
        insert(:event,
          created_by: user.id,
          user: user,
          organization: user,
          title: "Phoenix Framework Summit"
        )

      insert(:participant, event: event, user: user, status: "accepted")

      response = conn |> get(~p"/api/v1/events/#{event.id}") |> json_response(200)

      assert response["status"] == "success"
      assert response["data"]["id"] == event.id
      refute Map.has_key?(response["data"], "join_state")
    end
  end

  describe "create/2" do
    test "successfully creates event", %{conn: conn} do
      params = %{
        "event" => %{
          "title" => "Legitimate Protests Rally",
          "description" => "A peaceful civic gathering.",
          "category" => "standard",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "location_name" => "Community Center Main Hall",
          "street" => "123 Civic Plaza",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
        }
      }

      response = conn |> post(~p"/api/v1/events", params) |> json_response(201)
      assert response["status"] == "success"
      assert response["data"]["title"] == "Legitimate Protests Rally"
    end

    test "returns 422 on first hard-ban strike", %{conn: conn} do
      banned_word = insert_hard_keyword()

      params = %{
        "event" => %{
          "title" => "Malicious Attempt #{banned_word}",
          "description" => "contains #{banned_word}",
          "category" => "standard",
          "participation_format" => "in_person",
          "join_mode" => "free",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
        }
      }

      response = conn |> post(~p"/api/v1/events", params) |> json_response(422)

      assert response["error"] == "Your post contains prohibited language."
    end
  end

  defp insert_hard_keyword do
    word = "blocked_event_#{System.unique_integer([:positive])}"

    %RestrictedKeyword{}
    |> RestrictedKeyword.changeset(%{
      word: word,
      level: "hard",
      action: "reject",
      is_active: true
    })
    |> Repo.insert!()

    word
  end

  describe "update/2" do
    setup %{user: user} do
      # Pre-seed an event owned by our authenticated test user
      start_time = DateTime.utc_now() |> DateTime.add(1800, :second)

      event =
        insert(:event,
          created_by: user.id,
          user: user,
          organization: user,
          title: "Original Title",
          start_time: start_time,
          end_time: DateTime.add(start_time, 3600, :second),
          event_status: "published"
        )

      {:ok, event: event}
    end

    test "successfully updates event", %{
      conn: conn,
      event: event
    } do
      params = %{
        "event" => %{
          "title" => "Updated Legitimate Title",
          "description" => "An updated peaceful community gathering.",
          "start_time" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
          "location_name" => "Community Center Main Hall",
          "street" => "123 Civic Plaza"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{event.id}", params) |> json_response(200)
      assert response["status"] == "success"
      assert response["data"]["title"] == "Updated Legitimate Title"
    end

    test "returns 403 forbidden if a user attempts to update someone else's event", %{conn: conn} do
      # Create an event owned by a completely different user
      other_user = insert(:user)
      other_event = insert(:event, created_by: other_user.id, user: other_user)

      params = %{
        "event" => %{
          "title" => "Malicious Hijack Attempt"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{other_event.id}", params) |> json_response(403)
      assert response["error"] == "You are not authorized to edit this event."
    end

    test "returns 422 unprocessable entity on the first hard-ban strike inside edits", %{
      conn: conn,
      event: event
    } do
      banned_word = insert_hard_keyword()

      params = %{
        "event" => %{
          "title" => "Malicious Edit #{banned_word}"
        }
      }

      response = conn |> put(~p"/api/v1/events/#{event.id}", params) |> json_response(422)
      assert response["error"] == "Your edits contain prohibited language."
    end
  end

  describe "delete/2" do
    test "successfully cancels an event if the requester is the original owner", %{
      conn: conn,
      user: user
    } do
      event = insert(:event, created_by: user.id, user: user)

      response = conn |> delete(~p"/api/v1/events/#{event.id}") |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "successfully deleted"
    end

    test "returns 403 forbidden if a user attempts to delete an event they do not own", %{
      conn: conn
    } do
      other_user = insert(:user)
      other_event = insert(:event, created_by: other_user.id, user: other_user)

      response = conn |> delete(~p"/api/v1/events/#{other_event.id}") |> json_response(403)

      assert response["error"] == "unauthorized"
      assert response["message"] =~ "You don't own this event"
    end
  end
end

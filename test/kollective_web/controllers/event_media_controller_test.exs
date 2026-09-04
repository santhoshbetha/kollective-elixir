# test/kollective_web/controllers/event_media_controller_test.exs
defmodule Kollective.EventsMock do
  # ⚡ Real execution fallbacks matching all your controller context parameters
  def generate_upload_url(_user, _event_id, "party.jpg", "chat") do
    {:ok, %{"url" => "https://amazonaws.com", "fields" => %{"key" => "party.jpg"}}}
  end

  def generate_upload_url(_user, _event_id, "party.jpg", "invalid_type") do
    {:error, :invalid_type}
  end

  def generate_upload_url(_user, _event_id, "party.jpg", _) do
    {:error, :timeout}
  end

  def list_event_media(_event_id) do
    [%{"id" => "1", "url" => "https://kollective.com"}]
  end

  def hide_event_media(_user, "authorized_id"), do: {:ok, :hidden}
  def hide_event_media(_user, "forbidden_id"), do: {:error, :unauthorized}
  def hide_event_media(_user, _), do: {:error, :not_found}
end

defmodule KollectiveWeb.EventMediaControllerTest do
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

  describe "presign_upload/2 (GET /api/v1/events/:event_id/media/presign)" do
    setup %{user: user} do
      event = insert(:event, user: user, organization: user)
      {:ok, event: event}
    end

    test "returns a valid presigned upload URL payload on success", %{conn: conn, event: event} do
      params = %{"filename" => "party.jpg", "type" => "chat"}

      response =
        conn
        |> get(~p"/api/v1/events/#{event.id}/media/presign", params)
        |> json_response(200)

      assert response["url"] == "https://amazonaws.com"
      assert response["fields"]["key"] == "party.jpg"
    end

    test "returns 400 bad_request when asset type identifier is invalid", %{
      conn: conn,
      event: event
    } do
      params = %{"filename" => "party.jpg", "type" => "invalid_type"}

      response =
        conn
        |> get(~p"/api/v1/events/#{event.id}/media/presign", params)
        |> json_response(400)

      assert response["error"] =~ "Invalid asset type"
    end

    test "returns 503 service_unavailable when storage backend is unreachable", %{
      conn: conn,
      event: event
    } do
      params = %{"filename" => "party.jpg", "type" => "busy_trigger"}

      response =
        conn
        |> get(~p"/api/v1/events/#{event.id}/media/presign", params)
        |> json_response(503)

      assert response["error"] =~ "Upload subsystem busy"
    end
  end

  describe "index/2 (GET /api/v1/events/:event_id/media)" do
    test "returns a complete list of gallery items for an event", %{conn: conn} do
      event = insert(:event)

      response =
        conn
        |> get(~p"/api/v1/events/#{event.id}/media")
        |> json_response(200)

      assert %{"data" => [item]} = response
      assert item["url"] == "https://kollective.com"
    end
  end

  describe "hide/2 (DELETE /api/v1/events/media/:comment_id/hide)" do
    test "successfully evicts media from gallery when the requester is an authorized organizer",
         %{conn: conn} do
      response =
        conn
        |> delete(~p"/api/v1/events/media/authorized_id/hide")
        |> json_response(200)

      assert response["status"] == "success"
      assert response["message"] =~ "successfully evicted"
    end

    test "returns 403 forbidden if requester does not have administrative rights to the node", %{
      conn: conn
    } do
      response =
        conn
        |> delete(~p"/api/v1/events/media/forbidden_id/hide")
        |> json_response(403)

      assert response["error"] == "unauthorized"
    end

    test "returns 404 not_found if the media entry does not exist", %{conn: conn} do
      response =
        conn
        |> delete(~p"/api/v1/events/media/missing_id/hide")
        |> json_response(404)

      assert response["error"] == "not_found"
    end
  end
end

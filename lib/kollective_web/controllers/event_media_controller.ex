# lib/kollective_web/controllers/event_media_controller.ex
defmodule KollectiveWeb.EventMediaController do
  use KollectiveWeb, :controller
  alias Kollective.Events.Events

  # GET /api/v1/events/:event_id/media/presign
  # Expected params: ?filename=party.jpg&type=chat
  def presign_upload(conn, %{"event_id" => event_id, "filename" => filename, "type" => type}) do
    user = conn.assigns.current_user

    case Events.generate_upload_url(user, event_id, filename, type) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :invalid_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid asset type. Must be banner, logo, or chat."})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Upload subsystem busy or misconfigured"})
    end
  end

  # GET /api/v1/events/:event_id/media
  def index(conn, %{"event_id" => event_id}) do
    gallery_items = Events.list_event_media(event_id)
    json(conn, %{data: gallery_items})
  end

  # DELETE /api/v1/events/media/:comment_id/hide
  def hide(conn, %{"comment_id" => comment_id}) do
    organizer = conn.assigns.current_user

    case Events.hide_event_media(organizer, comment_id) do
      {:ok, :hidden} ->
        json(conn, %{
          status: "success",
          message: "Image successfully evicted from the community history."
        })

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "unauthorized"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end

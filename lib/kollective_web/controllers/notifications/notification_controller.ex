# lib/kollective_web/controllers/notifications/notification_controller.ex
defmodule KollectiveWeb.NotificationController do
  use KollectiveWeb, :controller
  alias Kollective.Notifications.Notifications
  alias KollectiveWeb.NotificationJSON

  # ─── ACTION 1: LIST CHRONOLOGICAL ACTIVITY ALERTS ───
  # GET /api/v1/notifications?limit=20&cursor=01J0A...
  def index(conn, params) do
    user = conn.assigns.current_user

    # Fetch alerts with look-ahead cursor support in exactly one database pass
    alerts = Notifications.list_user_notifications(user.id, params)
    next_cursor = if alerts != [], do: List.last(alerts).id, else: nil

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: NotificationJSON.index(%{notifications: alerts}),
      next_cursor: to_string(next_cursor)
    })
  end

  # POST /api/v1/notifications/mark_as_read
  def mark_as_read(conn, _params) do
    user_id = conn.assigns.current_user.id
    {count, _} = Notifications.mark_all_as_read(user_id)

    conn
    |> put_status(:ok)
    |> json(NotificationJSON.marked_as_read(count))
  end

  # GET /api/v1/notifications/unread_count
  def unread_count(conn, _params) do
    user_id = conn.assigns.current_user.id
    count = Notifications.count_unread_notifications(user_id)

    conn
    |> put_status(:ok)
    |> json(NotificationJSON.unread_count(count))
  end
end

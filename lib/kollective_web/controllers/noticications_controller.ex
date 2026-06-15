#  Phoenix Controller for mark_as_read to see how to return the success status to React
defmodule KollectiveWeb.NotificationController do
  use KollectiveWeb, :controller
  alias Kollective.Notifications.Notifications

  # POST /api/notifications/mark_as_read
  def mark_as_read(conn, _params) do
    user_id = conn.assigns.current_user.id

    # 1. Update the database
    {count, _} = Notifications.mark_all_as_read(user_id)

    # 2. Return success to React
    json(conn, %{
      status: "success",
      message: "#{count} notifications marked as read"
    })
  end

  # GET /api/notifications/unread_count
  def unread_count(conn, _params) do
    user_id = conn.assigns.current_user.id
    count = Notifications.count_unread_notifications(user_id)

    json(conn, %{count: count})
  end
end

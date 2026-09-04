# lib/kollective_web/views/notification_json.ex
defmodule KollectiveWeb.NotificationJSON do
  @moduledoc """
  Unified Standalone Notification Serializer.
  Outputs clean timeline activity shapes safely for the React frontend.
  """

  def index(%{notifications: notifications}) do
    Enum.map(notifications, &data/1)
  end

  def data(notification) do
    %{
      id: to_string(notification.id),
      # "mention", "reply", "follow", "upvote"
      type: notification.type,
      is_read: notification.read || false,
      preview_text:
        Map.get(notification.metadata || %{}, "preview") ||
          Map.get(notification.metadata || %{}, "message") ||
          Map.get(notification.metadata || %{}, :preview) ||
          Map.get(notification.metadata || %{}, :message) ||
          "interacted with your profile.",
      inserted_at: Calendar.strftime(notification.inserted_at, "%Y-%m-%dT%H:%M:%SZ"),

      # Actor Metadata profile footprint
      actor: %{
        id: to_string(notification.actor.id),
        username: notification.actor.username,
        avatar_url: notification.actor.avatar_url || "/default-avatar.jpg"
      },

      # Target metadata maps allow React to route clicks dynamically
      target: %{
        id: to_string(notification.target_id),
        # "Post", "Event", "User"
        type: notification.target_type
      }
    }
  end
end

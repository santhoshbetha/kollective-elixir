# lib/kollective_web/controllers/notifications/notification_json.ex
defmodule KollectiveWeb.NotificationJSON do
  @moduledoc """
  Unified Standalone Notification Serializer.
  Outputs clean timeline activity shapes safely for the React frontend.
  """

  alias Kollective.Accounts.User

  @doc """
  Serializes a list of notification records.
  """
  def index(%{notifications: notifications}) do
    Enum.map(notifications, &data/1)
  end

  def index(notifications) when is_list(notifications) do
    Enum.map(notifications, &data/1)
  end

  @doc """
  Serializes a single notification record.
  """
  def show(%{notification: notification}) do
    %{data: data(notification)}
  end

  def show(notification) do
    %{data: data(notification)}
  end

  @doc """
  Formats unread notification count response.
  """
  def unread_count(count) do
    %{status: "success", count: count, unread_count: count}
  end

  @doc """
  Formats marked as read response.
  """
  def marked_as_read(count) do
    %{
      status: "success",
      message: "#{count} notifications marked as read"
    }
  end

  @doc """
  Serializes a single notification entity.
  """
  def data(notification) do
    %{
      id: to_string(notification.id),
      # "mention", "reply", "follow", "upvote"
      type: notification.type,
      is_read: notification.read || false,
      preview_text: preview_text(notification),
      inserted_at: format_timestamp(notification.inserted_at),

      # Actor Metadata profile footprint
      actor: serialize_actor(notification.actor),
      user: serialize_actor(notification.actor),

      # Target metadata maps allow React to route clicks dynamically
      target: %{
        id: to_string(notification.target_id),
        # "Post", "Event", "User"
        type: notification.target_type
      }
    }
  end

  defp preview_text(notification) do
    metadata = notification.metadata || %{}

    Map.get(metadata, "preview") ||
      Map.get(metadata, "message") ||
      Map.get(metadata, :preview) ||
      Map.get(metadata, :message) ||
      "interacted with your profile."
  end

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  end

  defp format_timestamp(_), do: nil

  defp serialize_actor(%User{} = actor) do
    %{
      id: to_string(actor.id),
      username: actor.username,
      name: actor.display_name || actor.username,
      avatar: actor.avatar_url || "/default-avatar.jpg",
      avatar_url: actor.avatar_url || "/default-avatar.jpg"
    }
  end

  defp serialize_actor(%{id: id, username: username} = actor) do
    %{
      id: to_string(id),
      username: username,
      name: Map.get(actor, :name) || Map.get(actor, :display_name) || username,
      avatar: Map.get(actor, :avatar_url) || "/default-avatar.jpg",
      avatar_url: Map.get(actor, :avatar_url) || "/default-avatar.jpg"
    }
  end

  defp serialize_actor(_), do: nil
end

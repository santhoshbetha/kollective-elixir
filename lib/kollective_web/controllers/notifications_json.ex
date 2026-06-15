defmodule KollectiveWeb.NotificationsJSON do
  alias Kollective.Notifications.Notification

  def index(%{notifications: notifications}) do
    %{data: for(n <- notifications, do: data(n))}
  end

  def show(%{notification: notification}) do
    %{data: data(notification)}
  end

  def data(%Notification{} = n) do
    %{
      id: n.id,
      type: n.type,
      actor: %{
        id: n.actor_id,
        username: n.actor.username
      },
      target_id: n.target_id,
      target_type: n.target_type,
      # Call the link generator here
      url: get_link(n),
      inserted_at: n.inserted_at
    }
  end

  # The "get_link" logic
  defp get_link(n) do
    case n.target_type do
      "User" -> "/users/#{n.target_id}"
      "Post" -> "/posts/#{n.target_id}"
      "Comment" -> "/posts/#{n.post_id}#comment-#{n.target_id}"
      _ -> nil
    end
  end

  #list_notifications query to show a user their full history of follows, mentions, and reblogs
  def data2(notification) do
    %{
      id: notification.id,
      type: notification.type, # "follow", "mention", "reblog"
      inserted_at: notification.inserted_at,
      actor: %{
        id: notification.actor.id,
        username: notification.actor.username,
        avatar_url: notification.actor.avatar_url
      },
      # Only include post data if the notification is linked to one
      post: if notification.post do
        %{
          id: notification.post.id,
          content: notification.post.content
        }
      else
        nil
      end
    }
  end

end

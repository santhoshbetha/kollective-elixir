# "User Online/Offline" status? This uses the exact same Presence setup but tracks the user globally on a
# user:public channel.

# To implement Global Online/Offline Status using Phoenix Presence, you'll create a public channel that
# every active user joins. This allows your React app to show a green dot next to usernames in the
# sidebar or on profiles without hitting the database for "last seen" checks.
defmodule KollectiveWeb.UserPublicChannel do
  use KollectiveWeb, :channel
  alias KollectiveWeb.Presence

  def join("user:public", _params, socket) do
    # 1. Start tracking this user's online status
    send(self(), :after_join)
    {:ok, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second)),
        username: socket.assigns.username
      })

    # 2. Push the current list of everyone online to the new user
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    user_id = socket.assigns.user_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Update the database only once upon total disconnection
    Kollective.Accounts.Accounts.update_user_last_seen(user_id, now)

    :ok
  end
end

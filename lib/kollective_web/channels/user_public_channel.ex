# "User Online/Offline" status? This uses the exact same Presence setup but tracks the user globally on a
# user:public channel.

# To implement Global Online/Offline Status using Phoenix Presence, you'll create a public channel that
# every active user joins. This allows your React app to show a green dot next to usernames in the
# sidebar or on profiles without hitting the database for "last seen" checks.

# This module implements a global, memory-resident online/offline tracking system using Phoenix Presence.

# Instead of forcing your backend to constantly run database queries (like UPDATE users SET last_seen = NOW())
# every single time a user clicks around your app, this channel handles online statuses entirely inside Erlang's
# in-memory storage (ETS/distributed tracking).

defmodule KollectiveWeb.UserPublicChannel do
  use KollectiveWeb, :channel
  alias KollectiveWeb.Presence

  # The Global Topic Connection
  # Unlike the private user_notifications:${userId} or room:${roomId} channels which isolate users,
  # every single logged-in user in your entire application joins this exact same channel. It acts as a global virtual lobby.
  def joinX("user:public", _params, socket) do
    # 1. Start tracking this user's online status
    send(self(), :after_join)
    {:ok, socket}
  end

  def join("user:public", _payload, socket) do
    if socket.assigns[:is_authenticated] do
      # Track authenticated users uniquely by their database ID string
      send(self(), :track_presence)
      {:ok, socket}
    else
      # Guest visitors join as read-only listeners without incrementing total metrics counts
      {:ok, socket}
    end
  end

  def handle_info(:track_presence, socket) do
    # Tracking the User in Memory
    # The moment a user connects, Phoenix registers their user_id and metadata (username, online_at)
    # into the distributed memory cluster. This state is instantly synchronized across all your server nodes automatically.
    user_id = to_string(socket.assigns.user_id)

    username =
      cond do
        user = socket.assigns[:user] -> user.username
        name = socket.assigns[:username] -> name
        true -> "anonymous"
      end

    {:ok, _} =
      Presence.track(socket, user_id, %{
        device_id: socket.id,
        joined_at: inspect(System.system_time(:second)),
        online_at: System.system_time(:second),
        username: username
      })

    # 2. Push the current list of everyone online to the new user
    # Pushing the Presence State Snapshot
    # This pushes the master list of everyone currently online down to the joining user's React app.
    # Phoenix will automatically broadcast a delta event (presence_diff) to everyone else in the lobby to announce that this user has arrived.
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # The Database Write Saver (terminate/2)
  # This is the biggest performance optimization in the file. Instead of hitting PostgreSQL every couple of minutes to keep a
  # "last seen" timestamp fresh, the app completely ignores the database while the user is active.

  # Only when the user closes their browser tab or logs out—triggering the WebSocket disconnect—does the
  # terminate/2 lifecycle hook fire, committing a single, clean last_seen timestamp update to the database.
  def terminate(_reason, socket) do
    if user_id = socket.assigns[:user_id] do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Update the database only once upon total disconnection
      Kollective.Accounts.Accounts.update_user_last_seen(user_id, now)
    end

    :ok
  end
end

# For user presence tracking and real-time notifications, we use Phoenix Channels and Presence.
defmodule KollectiveWeb.UserChannel do
  use KollectiveWeb, :channel
  alias KollectiveWeb.Presence
  # Only include handle_out if you explicitly use intercept
  intercept ["some_event"]

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    # SECURITY GUARD: Guarantee users can only subscribe to their own rooms
    if to_string(socket.assigns.user_id) == user_id do
      # Async side-effect task: Registers the online marker immediately
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Stringify the ID cleanly to use as the unique presence tracker tracking key
    user_id_string = to_string(socket.assigns.user_id)

    # 🟢 FIXED: The second argument is now the isolated tracking key (the user's ID)
    {:ok, _} =
      Presence.track(socket, user_id_string, %{
        online_at: System.system_time(:second)
      })

    # Push the current presence state snapshot out to the React frontend client
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Keep this if you are using handle_out/3 to intercept and modify broadcasts sitewide
  @impl true
  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end

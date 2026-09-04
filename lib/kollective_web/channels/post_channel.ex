# This file implements a real-time comment/reply stream for a specific post thread (e.g., viewing a post details page in React)
# while solving a major social media UI challenge: personalizing dynamic data (like "Have I liked this comment?")
# for thousands of concurrent users simultaneously.

#  Core Purpose: Real-Time Threads with Dynamic Personalization
#
# When a new comment/reply is posted to a thread, the backend broadcasts the raw reply payload to every user currently looking at
# that post details screen. However, in a social app, the UI needs to display a filled-in heart icon if the viewing user has liked the reply,
# and an empty heart if they haven't. Because thousands of different users are watching the same thread, the server cannot broadcast
# a single identical message to everyone.
#
# This channel uses an Event Interceptor to intercept the message right before it leaves the server, customize it for each specific viewer,
# and then push it down the WebSocket.

defmodule KollectiveWeb.PostChannel do
  use KollectiveWeb, :channel
  alias Kollective.Accounts.Accounts
  alias Kollective.Posts.Posts

  # Register the event interceptor so handle_out/3 is allowed to run
  # This tells Phoenix: "When a new_reply event is broadcasted to this channel, do not send it straight to the client.
  # Stop, and hand it to the handle_out/3 function first."
  intercept ["new_reply"]

  # The Topic Connection ("post_details:" <> _root_id)
  # When a user opens a post in React to view its replies, they join this channel using the post's database ID (e.g., post_details:712).
  @impl true
  def join("post_details:" <> _root_id, _payload, socket) do
    # Optional: Load initial data state to minimize API handshakes
    {:ok, socket}
  end

  @impl true
  def handle_out("new_reply", reply, socket) do
    # 1. FIX: Fetch the actual authenticated User struct using the socket's assigned user_id
    # 3. Resolving the Current Viewer
    # Because handle_out/3 runs inside the isolated process memory of this specific user's unique WebSocket connection,
    #  socket.assigns.user_id points to the exact person looking at the screen.
    current_user = Accounts.get_user(socket.assigns.user_id)

    # 2. Run your O(1) batch pre-fetch hydration loop instead of an N+1 query string crash
    # Pass the clean current_user struct down to color heart icons correctly.
    # The Hydration Loop (The "Heart Icon" Solver)
    # This runs a fast check against the database to populate virtual boolean flags (like has_liked: true or has_liked: false) relative to the current_user.
    [hydrated_reply] = Posts.hydrate_virtual_fields([reply], current_user)

    # 3. Output matching your exact PostJSON layout contract payload
    # Serialization and Client Push
    # It transforms the newly customized Elixir struct into the exact clean JSON format your React frontend expects, ensuring your network payload matches your standard REST API data contracts perfectly.
    push(socket, "new_reply", %{reply: KollectiveWeb.PostJSON.show(hydrated_reply)})
    {:noreply, socket}
  end
end

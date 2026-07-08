defmodule KollectiveWeb.PostChannel do
  use KollectiveWeb, :channel
  alias Kollective.Accounts.Accounts
  alias Kollective.Posts.Posts

  # Register the event interceptor so handle_out/3 is allowed to run
  intercept ["new_reply"]

  @impl true
  def join("post_details:" <> _root_id, _payload, socket) do
    # Optional: Load initial data state to minimize API handshakes
    {:ok, socket}
  end

  @impl true
  def handle_out("new_reply", reply, socket) do
    # 1. FIX: Fetch the actual authenticated User struct using the socket's assigned user_id
    current_user = Accounts.get_user(socket.assigns.user_id)

    # 2. Run your O(1) batch pre-fetch hydration loop instead of an N+1 query string crash
    # Pass the clean current_user struct down to color heart icons correctly
    [hydrated_reply] = Posts.hydrate_virtual_fields([reply], current_user)

    # 3. Output matching your exact PostJSON layout contract payload
    push(socket, "new_reply", %{reply: KollectiveWeb.PostJSON.show(hydrated_reply)})
    {:noreply, socket}
  end
end

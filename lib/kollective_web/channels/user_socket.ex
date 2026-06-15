defmodule KollectiveWeb.UserSocket do
  use Phoenix.Socket
  alias Kollective.Accounts.Accounts

  ## Channels
  channel "notifications:*", KollectiveWeb.NotificationsChannel
  channel "user:*", KollectiveWeb.UserChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # Verify the token and assign the user
    # Verify the user is NOT suspended during connection
    case Accounts.get_user_by_session_token(token) do
      nil ->
        :error
      {:ok, %{suspended_at: nil} = user} ->
        {:ok, socket
          |> assign(:user, user)
          |> assign(:user_id, user.id)
          |> assign(:is_authenticated, true)}
      {:ok, _suspended_user} ->
        :error # Reject connection for suspended users
       _ -> :error
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     KollectiveWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  # This allows us to target a specific user by their UUID
  def id(socket), do: "users_socket:#{socket.assigns.current_user.id}"

end
